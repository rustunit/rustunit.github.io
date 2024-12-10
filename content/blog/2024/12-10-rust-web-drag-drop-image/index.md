+++
title = "Drag & Drop Images into Bevy 0.15 on the web"
date = 2024-12-10
[extra]
tags=["rust","bevy","web"] 
hidden = false
custom_summary = "In this post, we talk about how to integrate web native APIs via WASM with Bevy."
+++

<img src="demo.gif" alt="demo" style="width: 50%; max-width: 500px" class="inline-img" />

In this post, we talk about how to integrate web native APIs via WASM with Bevy.

We utilize the recently released [bevy_channel_trigger](https://crates.io/crates/bevy_channel_trigger) crate, [wasm-bindgen](https://github.com/rustwasm/wasm-bindgen) and [gloo](https://github.com/rustwasm/gloo).

If you want to play with the code and tinker with it, you can find it on [GitHub](https://github.com/rustunit/bevy_web_drop_image_as_sprite).

# What is the use case?

In this example, we want to allow the user to drop a *PNG* image into our Bevy app running in the Browser. The app should load the image into the Bevy Asset machinery and display it like any other image file. See the animation to the right visualizing this.

The steps to making this work are:

1. Prepare the DOM to receive drop events
2. Handle Drop-Events (containing file data)
3. Forward events to Bevy
4. Receive and load image data in Bevy

Let's dive into the details of each of these steps.

## 1. Prepare the DOM to receive drop events

The first thing we need to do is to register the event listeners for `dragover` and `drop` on the DOM element we want to receive the drop events. We will be using wasm-bindgen and gloo to be able to do this right from our rust code:
    
```rust
pub fn register_drop(id: &str) -> Option<()> {
    let doc = gloo::utils::document();
    let element = doc.get_element_by_id(id)?;

    EventListener::new_with_options(
        &element,
        "dragover",
        EventListenerOptions::enable_prevent_default(),
        move |event| {
            let event: DragEvent = event.clone().dyn_into().unwrap();
            event.stop_propagation();
            event.prevent_default();

            event
                .data_transfer()
                .unwrap()
                .set_drop_effect("copy");
            event
                .data_transfer()
                .unwrap()
                .set_effect_allowed("all");
        },
    )
    .forget();

    //...
}
```

You can find the full function [here](https://github.com/rustunit/bevy_web_drop_image_as_sprite/blob/10eb3fca875eb0edb608cf8903b314fa5cebcac9/src/web/web.rs#L7) but the important part is that the code is essentially 1:1 from how you would solve this in vanilla javascript translated to rust while looking at the [web_sys docs](https://docs.rs/web-sys/latest/web_sys/) for reference.

> Note that we are setting the `drop_effect` and `effect_allowed` here to make sure the browser will allow us to receive the drop and to show this on the mouse cursor to the user as well.

The handling of the `drop` event is a bit more involved as we need to extract the file data from the event and forward it to Bevy. We will cover this in the next section.

## 2. Handle Drop-Events

The following code is the second half of the `register_drop` function we started in the previous section. It handles the `drop` event and forwards the file data to Bevy:

```rust
EventListener::new_with_options(
    &element,
    "drop",
    EventListenerOptions::enable_prevent_default(),
    move |event| {
        let event: DragEvent = event.clone().dyn_into().unwrap();
        event.stop_propagation();
        event.prevent_default();

        let transfer = event.data_transfer().unwrap();
        let files = transfer.items();

        for idx in 0..files.length() {
            let file = files.get(idx).unwrap();
            let file_info = file.get_as_file().ok().flatten().unwrap();

            let file_reader = FileReader::new().unwrap();

            {
                let file_reader = file_reader.clone();
                let file_info = file_info.clone();

                // register the listener for when the file is loaded
                EventListener::new(&file_reader.clone(), "load", move |_event| {
                    // read the binary data from the file
                    let result = file_reader.result().unwrap();
                    let result = web_sys::js_sys::Uint8Array::new(&result);
                    let mut data: Vec<u8> = vec![0; result.length() as usize];
                    result.copy_to(&mut data);

                    // send the binary data to our bevy app logic
                    send_event(crate::web::WebEvent::Drop {
                        name: file_info.name(),
                        data,
                        mime_type: file_info.type_(),
                    });
                })
                .forget();
            }

            // this will start the reading and trigger the above event listener eventually
            file_reader.read_as_array_buffer(&file_info).unwrap();
        }
    },
)
.forget();
```
Find the full function code up on GitHub [here](https://github.com/rustunit/bevy_web_drop_image_as_sprite/blob/10eb3fca875eb0edb608cf8903b314fa5cebcac9/src/web/web.rs#L7).

Once again the way we handle the drop and extract the binary content of the file dropped is very similar to how you would do it in vanilla javascript. We are using the `FileReader` API to read the binary data and some metadata from the file and then forward it to Bevy via `send_event`.

We will look into how exactly we bridge the two worlds of DOM-events and Bevy-events in the next section.

You will notice a lot of un-idiomatic rust here just unwrapping instead of handling the errors. This is because we are in a demo and we want to keep the code as simple as possible. In a real-world application, you would want to handle the errors properly.

> We are using `.forget` in this demo for simplicity's sake which will leak the event listeners. Just like with `unwrap` it would be different in a real-world application - you would want to store the event listeners in a struct and drop them when they are no longer needed.

## 3. Forward events to Bevy

In the above event listener we are calling `send_event` to forward the file data to Bevy. Let's look at how this function works:

```rust
static SENDER: OnceLock<Option<ChannelSender<WebEvent>>> = OnceLock::new();

pub fn send_event(e: WebEvent) {
    let Some(sender) = SENDER.get().map(Option::as_ref).flatten() else {
        return bevy::log::error!("`WebPlugin` not installed correctly (no sender found)");
    };
    sender.send(e);
}
```

`ChannelSender` is a type from the `bevy_channel_trigger` that effectively is a multi-producer single-consumer channel (the sending part of it) that we can use to send events from the web side to the Bevy side. Exactly how we are going to receive these events in Bevy is covered in the next section.

> Our previous blog post dives into detail about how `bevy_channel_trigger` works and how you can use it in your projects. You can find it [here](https://rustunit.com/blog/2024/11-15-bevy-channel-trigger).

## 4. Receive and load image data in Bevy

The final piece of the puzzle is the receiving side in Bevy to process a binary blob we expect to be an image file and load it as an `Image` Asset. If that succeeds we can start using it for rendering:

```rust
fn process_web_events(
    trigger: Trigger<WebEvent>,
    assets: Res<AssetServer>,
    mut sprite: Query<&mut Sprite>,
) {
    let e = trigger.event();
    let WebEvent::Drop {
        data,
        mime_type,
        name,
    } = e;

    let Ok(image) = Image::from_buffer(
        data,
        ImageType::MimeType(mime_type),
        CompressedImageFormats::default(),
        true,
        ImageSampler::Default,
        RenderAssetUsages::RENDER_WORLD,
    ) else {
        warn!("could not load image: '{name}' of type {mime_type}");
        return;
    };

    let handle = assets.add(image);

    sprite.single_mut().image = handle;
}
```

The above function `process_web_events` is registered as an observer in our `App` and triggers any time the `send_event` function from earlier is called.

At the core of it, we are trying to create an [`Image`](https://docs.rs/bevy/latest/bevy/image/struct.Image.html#method.from_buffer) from a buffer, providing the mime-type to help choose the encoder. If it fails we either have no way to parse the file format as an image or the dropped file was no image in the first place and we return. 

If the image loading was successful we keep the image as an asset and use the `Handle<Image>` to swap out the sprite moving up and down the screen.

# Conclusion

In the demo, we have shown how to integrate web native APIs via WASM with Bevy. In this post, we focused on the key aspects of the code base. There is more though, feel free to dig into the project on GitHub, run it, and tinker with it.

Bevy is a strong tool to bring interactive applications to the web and with the help of WASM and the right crates you can integrate web native APIs with ease.

---

Do you need support building your Bevy or Rust project? Our team of experts can support you! [Contact us.](@/contact.md)