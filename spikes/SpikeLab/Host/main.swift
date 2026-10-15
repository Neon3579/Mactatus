// SpikeLab 호스트: 권한(손쉬운 사용·화면 기록·블루투스)은 이 앱에 한 번만 준다.
// 실제 테스트 코드는 dylib로 따로 빌드해서 불러오므로, 테스트를 고쳐도 권한이 풀리지 않는다.
// 사용: SpikeLab <dylib 경로> <테스트 이름> <로그 경로> [추가 인자]
import AppKit
import Darwin

let args = CommandLine.arguments
guard args.count >= 4 else {
    fputs("usage: SpikeLab <dylib> <test> <log> [extra]\n", stderr)
    exit(2)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

guard let handle = dlopen(args[1], RTLD_NOW) else {
    try? String(cString: dlerror()).write(toFile: args[3], atomically: true, encoding: .utf8)
    exit(3)
}
guard let symbol = dlsym(handle, "spike_run") else { exit(4) }

typealias Entry = @convention(c) (UnsafePointer<CChar>, UnsafePointer<CChar>, UnsafePointer<CChar>) -> Void
let entry = unsafeBitCast(symbol, to: Entry.self)
let extra = args.count > 4 ? args[4] : ""

DispatchQueue.main.async {
    args[2].withCString { test in
        args[3].withCString { log in
            extra.withCString { entry(test, log, $0) }
        }
    }
}
app.run()
