+++
title = "iOS Deep-Linking with Bevy"
date = 2025-05-18
[extra]
tags=["rust","bevy","mobile"]
custom_summary = "Deep-Linking unlocked on iOS with Bevy"
+++

Until very recently Bevy iOS apps had a hard time reading deep linking information. Bevy uses [winit](https://github.com/rust-windowing/winit) by default for its platform integrations like window lifecycle management. On iOS winit used to implement and register its own `AppDelegate` to receive app life cycle hooks/calls.

Users of Bevy therefore had only one inconvenient option to receive these hooks: Ditch winit and roll this themselves.

As of `winit 0.30.10` ([see release](https://github.com/rust-windowing/winit/releases/tag/v0.30.10)) we can now do much better.

# What is the use case?

"Deep linking" means that a link leads to our app being opened or foregrounded and the app knowing *that* and *what* url triggered it. The iOS jargon for this is [URL Scheme](https://developer.apple.com/documentation/xcode/defining-a-custom-url-scheme-for-your-app). Some example use cases for this are:

* Sharing specific content inside the app (imagine a user sharing their game profile with a friend)
* File-Sharing (more on that later)
* Advertisement attribution tracking (not covered here)

> You might wonder why this is relevant for File-Sharing on iOS. It turns out that the code that triggers your app to open after sharing a file with it is actually just using such a URL scheme to do that.

# High level steps

1. Configure your url schema in xcode
2. Add a handler for the `application:(_:open:options:)` call. ([see docs](https://developer.apple.com/documentation/UIKit/UIApplicationDelegate/application(_:open:options:)))
3. Handle deep link properly

## Configure your url schema

For iOS to open your app on a click on a specifically crafted URL we have to adapt our `Info.plist` file like so:

```xml
...
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleURLName</key>
    <string>com.rustunit.tinytakeoff</string>
    <key>CFBundleURLSchemes</key>
    <array>
      <string>tinytakeoff</string>
    </array>
  </dict>
</array>
```

With this our game [tinytakeoff](https://tinytakeoff.com) will be opened when clicking on URL looking this: `tinytakeoff://fooobar?param=value`

Alternatively you can also make that change via the XCode UI, see the [docs to register your URL scheme](https://developer.apple.com/documentation/xcode/defining-a-custom-url-scheme-for-your-app#Register-your-URL-scheme).

So far these steps were possible already before and lead to your app being opened or foregrounded based on a click on such a URL.

What was not possible was step 2 and 3 to actually make use of that information inside your Bevy app.

## Receive app open options

Thanks to the [objc2](https://github.com/madsmtm/objc2) crate we can use native objc APIs without having to write objc but pure rust instead. The underlying code looks like magic and uses a bunch of macros to accomplish this. The result is that we can abstract this away into a conventient rust only crate: [bevy_ios_app_delegate](https://github.com/rustunit/bevy_ios_app_delegate).

Using this crate hooking into this open url life cycle call of the `AppDelegate` becomes as easy as this snippet of bevy setup code:

```rust
pub fn plugin(app: &mut App) {
  // bevy setup skipped here...

  // register our crates plugin (this is a noop on non ios platforms)
  app.add_plugins(IosAppDelegatePlugin);

  // register observer that triggers if open url app delegate was called (either by app opening or foregrounding after a click on a URL scheme)
  app.add_observer(|trigger: Trigger<AppDelegateCall>| {
    info!("app delegate call: {:?}", trigger.event());
  });
}
```

## Handle deep link

This is of course very application dependant. Here are a few example of what to do:

| Link action | App behaviour |
| --- | --- |
| game user profile link | App opens the user profile of the user that created the link |
| a player's new record game run | The app shows this player's replay after clicking their link |
| file sharing  | A `ShareExtension` receives a file that it wants to share with your app and opens your app using a URL schema and the app can identify what file to open using the deep linking context |

# Further steps

**universal links**

Aside from the custom URL schema we described above, a regular web domain can be associated with your app and trigger opening it, this is called *universal linking* ([see apple docs](https://developer.apple.com/documentation/xcode/supporting-universal-links-in-your-app)) and requires yet another `AppDelegate` [call implementation](https://developer.apple.com/documentation/appkit/nsapplicationdelegate/application(_:continue:restorationhandler:)).

**push notification token**

Being able to make a custom `AppDelegate` implementation has more advantage than just for deep linking. We can now vastly simplify also the way we currently receive a push notification token in the [bevy_ios_notifications](https://github.com/rustunit/bevy_ios_notifications) crate. Receiving this token also happens via `AppDelegate` call and will be provided via the new `bevy_ios_app_delegate` crate soon.

Exciting times to build iOS apps using Bevy.

---

Do you need support building your Bevy or Rust project? Our team of experts can support you! [Contact us.](@/contact.md)
