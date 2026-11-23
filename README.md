# Duo Mix

Remote control mixers on your duo.

Duo Mix is a native SwiftUI mixing surface for iPhone Duo, iPad, and iPhone. Open the app to try a 32-input practice mix. The first hardware driver targets the **PreSonus StudioLive 32SX**. It connects directly over the local network. The outstanding milestone is a two-way control test on a physical 32SX.

<img src="docs/duo-demo.png" width="350" alt="A half-open Duo with input meters and channel faders above the hinge and a precision pad below.">

## Try the surface

Open `DuoMix.xcodeproj` in Xcode 27.2, choose the **DuoMix** scheme, select an iPhone Duo simulator, and press **Run**. The app also supports iOS and iPadOS 17 or later. For a physical device, choose your team in **Signing & Capabilities**.

The app opens in **Demo**. Drag anywhere on a channel’s fader lane to move the Chisel grip. A tap on the lane or channel name selects it. Tap **Mute** to mute that input. The bank fits as many whole strips as the window allows, with a 72-point minimum at standard text sizes. Use the arrows to page through the inputs.

The line across the grip marks the fader setting. The meter beside it and the dB reading above it show the incoming audio level. Demo generates local practice signals. In a live session the driver estimates dBFS from the console's input meter samples. **−∞** means digital silence. **—** means the app has no fresh sample. On a supported phone, the fader gives a light pickup, spaced ticks, and a firmer stop at either end.

| Surface | How to mix |
| --- | --- |
| Duo, half open like a laptop | The toolbar shares the top row with the system indicators when space allows. Faders fill the upper half down to the fold. Drag the lower pad for fine control of the selected input, or tap **−** or **+** to nudge one percentage point. |
| Duo, held like a book | A single bank continues on the other side of the hinge. Every strip fits fully on one side. |
| Open Duo, iPad, cover display, and ordinary iPhone | Faders fill the space below the connection and bank controls. |

## First test with the 32SX

1. Connect the mixer's **Control** Ethernet jack to a router's **LAN** port. Join that router's Wi-Fi on the phone. [PreSonus networking guide](https://pae-web.presonusmusic.com/downloads/products/pdf/Networking_for_StudioLive_Remote_Control_V2_EN_11102021.pdf)
2. In Duo Mix, tap **Demo → Scan for mixers** and allow Local Network access. Tap your mixer in the results. If needed, read its IP address from the console’s **UCNET** screen, enter it under **Manual connection**, and tap **Connect to mixer**. The default TCP port is **53000**. On the console, grant the connected device **FOH** permission for the main mix. [PreSonus device permissions](https://support.presonus.com/hc/en-us/articles/360056143232-StudioLive-Series-III-Why-are-my-Meters-Dark-Grayed-out-and-can-t-Control-my-Mixer-in-Universal-Control)
3. Choose an unused input and note its starting fader and mute state. Wait for **Live**, then compare the channel name, mute state, and fader position with the desk. Move the desk fader and toggle mute. Confirm both changes appear on the phone.
4. From the app, nudge the same fader and toggle mute. Watch the physical fader and mute light, and check that the changes also come back to the app. Restore the input's original settings. Compare the input meter with the console using a steady signal at a known level. Note both readings and confirm that removing the signal clears the meter.
5. Drop Wi-Fi briefly, change the unused input at the desk, then restore Wi-Fi. If the automatic retries finish first, tap **Offline** and reconnect. The first values after reconnect should match the desk. If a check fails, record the console firmware, input number, app status, which control you moved, and what the other end showed.

The **Demo** session runs locally. **Connecting** waits for the subscription reply and initial channel state. When you move a live control, **Awaiting desk** marks the value you requested. A matching console update confirms it. If a change stays unconfirmed for two seconds after your last input, the app opens a fresh read-only sync and displays the desk's actual settings. Every new connection starts without replaying earlier commands.

## Driver design

```text
Channel strips + fine pad
           ↕
       MixerStore
           ↕
       MixerDriver
        ├── DemoDriver       in-memory practice desk
        └── PreSonusDriver   TCP control + UDP input meters ↔ StudioLive
```

The surface consumes channel IDs, names, normalized fader travel, mute state, and input signal levels. The PreSonus driver translates them into console-specific messages. A second brand can implement the same driver contract. This build supports StudioLive discovery, manual connection, input faders, input mute, and input meters. Mix buses, pan, EQ, and scenes are future work.

**Scan for mixers** checks TCP port 53000 on the active Wi-Fi or Ethernet IPv4 subnet. On larger networks it searches the 256-address block containing the phone. It lists each mixer by its reported name and address after receiving a UCNET subscription reply and valid channel state, then closes the probe. Selecting a result opens the control session. Use manual connection for consoles outside the scanned block or on a custom port. [StudioLive UCNET protocol](https://featherbear.cc/presonus-studiolive-api/#high-level-overview)

## Research notes

- **StudioLive.** PreSonus documents the control network and Series III remote-mixing permissions. The community UCNET reference supplies TCP framing, parameter paths, and the compressed state layout. Its author reports tests on 16, 32SC, 16R, and 24R. Duo Mix decoded all 16 input channels from the author's published 16R recording at four TCP read sizes. The 32SX still needs a bench test, including whether the desk echoes this client's own writes. [PreSonus networking guide](https://pae-web.presonusmusic.com/downloads/products/pdf/Networking_for_StudioLive_Remote_Control_V2_EN_11102021.pdf) · [UCNET protocol research](https://featherbear.cc/presonus-studiolive-api/) · [Recorded 16R session](https://github.com/featherbear/presonus-studiolive-api/blob/7e9239cd64de21fab03168fc57503144061bdf6c/dumps/connect_and_idle_UC_SL16R.pcapng)
- **Fader feedback.** In a second recording, the desk answered input-fader writes with grouped positions (`MS/fdrs`). The driver matched all 100 requested positions to their recorded replies within one 16-bit step. This readback uses TCP and works independently of audio metering. [Recorded fader moves](https://github.com/featherbear/presonus-studiolive-api/blob/7e9239cd64de21fab03168fc57503144061bdf6c/dumps/line_ch1_volume%200-100.pcapng)
- **Input signal.** The desk sends a unicast UDP stream to a port registered over TCP. The driver reads input group 0 from `MS/levl`. It uses the community 32SC adapter’s estimate of 20 × log₁₀(sample / 65535). Calibration against a known signal on the 32SX is pending. [Series III meter protocol](https://featherbear.cc/presonus-studiolive-api/#metering) · [32SC conversion reference](https://github.com/zarfld/presonus-studiolive-mcp/blob/HEAD/packages/presonus-adapter/src/meter-summarizer.ts)
- **Multi-brand control.** Mixing Station uses a mixer profile and offers an offline mode. Duo Mix follows that model by keeping console messages inside a driver and exposing the same controls in demo mode. [Mixing Station manual](https://mixingstation.app/docs/getting-started/) · [Series III notes](https://mixingstation.app/docs/mixers/presonus/sl3/)
- **Duo.** Apple recommends sizing from the current window. Duo Bible's hinge-aware panes supplied the layout pattern here. The app reads SwiftUI's division region on iOS 27.1 and later. Sill's half-open trackpad informed the relative fader pad so your hand can stay below the display. [Apple Duo preparation guide](https://developer.apple.com/iphone-duo/prepare/) · [Sill](https://getsill.app/)
- **Mixing surfaces.** WING Copilot groups channel editing and metering by task. FLOW Mix brings named inputs, levels, and mute to small screens. Those references informed the channel bank and selected-channel pad. Fender lists Universal Control for iPhone and iPad and describes its StudioLive surface as iPad-optimized. [WING Copilot](https://apps.apple.com/us/app/wing-copilot/id1447618712) · [FLOW Mix](https://apps.apple.com/us/app/flow-mix/id1473097916) · [Fender Universal Control](https://apps.apple.com/us/app/fender-universal-control/id6755309706)

## Run the checks

Use **Product → Test** in Xcode with an iOS simulator selected. The suite exercises the mixer store, UCNET decoding, and a TCP loopback desk that checks both directions of control. The UI test operates the channel bank, mute switch, and precision pad. Physical fader movement, console permissions, and behavior on venue Wi-Fi require the bench test above.
