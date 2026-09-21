import Flutter
import UIKit

@main
class AppDelegate: FlutterAppDelegate {
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)
        GeneratedPluginRegistrant.register(with: self)

        guard let controller = window?.rootViewController as? FlutterViewController else {
            return result
        }

        let channel = FlutterMethodChannel(
            name: "congcong/spider",
            binaryMessenger: controller.binaryMessenger
        )
        channel.setMethodCallHandler { call, reply in
            guard call.method == "executeSpider",
                  let values = call.arguments as? [String: Any],
                  let api = values["api"] as? String,
                  let method = values["method"] as? String else {
                reply(FlutterError(code: "BAD_ARGUMENTS", message: "动态脚本参数无效", details: nil))
                return
            }

            let ext = values["ext"] as? String ?? ""
            let arguments = values["arguments"] as? [Any] ?? []
            Task {
                do {
                    let output = try await IOSSpiderRunner().call(
                        api: api,
                        ext: ext,
                        method: method,
                        arguments: arguments
                    )
                    await MainActor.run { reply(output) }
                } catch {
                    await MainActor.run {
                        reply(FlutterError(code: "SPIDER_ERROR", message: error.localizedDescription, details: nil))
                    }
                }
            }
        }

        return result
    }
}
