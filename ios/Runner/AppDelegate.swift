import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    PocketTTSPlugin.register(with: registrar(forPlugin: "PocketTTSPlugin")!)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
