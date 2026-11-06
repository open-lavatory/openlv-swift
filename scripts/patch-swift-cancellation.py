"""Add Swift task cancellation to UniFFI 0.32.2's generated async runtime.

Only throwing APIs opt in: UniFFI's infallible methods use try! and must not
throw CancellationError. Exact replacements make generator upgrades fail closed.
"""
import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1])
source = path.read_text()

def replace_once(old, new):
    global source
    if source.count(old) != 1:
        raise SystemExit(f"UniFFI template changed; review cancellation patch: {old[:80]!r}")
    source = source.replace(old, new, 1)

replace_once('fatalError("Cancellation not supported yet")', 'throw CancellationError()')
replace_once(
    '    freeFunc: (UInt64) -> (),\n    liftFunc:',
    '    freeFunc: (UInt64) -> (),\n    cancelFunc: (@Sendable (UInt64) -> Void)?,\n    liftFunc:',
)
replace_once(
    '''    let rustFuture = rustFutureFunc()
    defer {
        freeFunc(rustFuture)
    }
    var pollResult: Int8;''',
    '''    let rustFuture = rustFutureFunc()
    let cancellation = RustFutureCancellation(handle: rustFuture, cancel: cancelFunc)
    defer {
        cancellation.finish()
        freeFunc(rustFuture)
    }
    return try await withTaskCancellationHandler(operation: {
    var pollResult: Int8;''',
)
replace_once(
    '''        errorHandler: errorHandler
    ))
}

// Callback handlers for an async calls.''',
    '''        errorHandler: errorHandler
    ))
    }, onCancel: {
        cancellation.cancel()
    })
}

// Callback handlers for an async calls.''',
)

pattern = re.compile(
    r'(            freeFunc: ffi_openlv_ffi_rust_future_free_(\w+),\n)'
    r'(            liftFunc:.*?errorHandler: (\w+))', re.DOTALL
)
def add_cancel(match):
    callback = 'nil' if match[4] == 'nil' else f'ffi_openlv_ffi_rust_future_cancel_{match[2]}'
    return match[1] + f'            cancelFunc: {callback},\n' + match[3]

source, count = pattern.subn(add_cancel, source)
if count != 12:
    raise SystemExit(f"Expected 12 async APIs, found {count}; review cancellation patch")
path.write_text('// Cancellation support applied by scripts/patch-swift-cancellation.py.\n' + source)
