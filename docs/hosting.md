# Hosting and joining over the internet

How to play *Something in the Corn* with friends who are not on your home network. One person
hosts; up to three others join. Checked against `game/scripts/net.gd` and `main_menu.gd`
(2026-10-05).

## Contents

- [What the game uses](#what-the-game-uses)
- [Host and join](#host-and-join)
- [The easy way: a virtual LAN](#the-easy-way-a-virtual-lan)
- [The other way: forward a port on the host's router](#the-other-way-forward-a-port-on-the-hosts-router)
- [When it does not connect](#when-it-does-not-connect)
- [Open items](#open-items)

## What the game uses

- **UDP port 7777** (`Net.DEFAULT_PORT`). The game connects with Godot's ENet, which uses UDP
  only, never TCP ([Godot docs, ENetMultiplayerPeer](https://docs.godotengine.org/en/stable/classes/class_enetmultiplayerpeer.html)).
  The host listens on every network interface.
- **Another port:** start the game with `-- --port=N`. Everyone, host and joiners, must use the
  same N. The main menu shows the port in use on its bottom line; it cannot be changed there.
- **Voice chat** travels over the same connection (`addons/voice_chat`, on its own ENet channel),
  so it needs no extra port. It does need microphone access: Windows Settings > Privacy &
  security > Microphone, with desktop apps allowed, or recordings come out silent.
- **Everyone needs the same version** of the game. Nothing checks this yet; see
  [Open items](#open-items).

## Host and join

From the main menu: type your name, then

- **Host:** press **Host**. The address box is ignored when hosting.
- **Join:** type the host's address in the box and press **Join**.

From the command line (from the repo root, with Godot 4.7):

```
godot --path game -- --host --name=Host
godot --path game -- --join=ADDRESS --name=Friend
```

Add `--port=N` to both if you changed the port. The host waits in the lobby until everyone is in,
then presses **Start the day**.

## The easy way: a virtual LAN

A virtual LAN puts everyone's PCs on one private network over the internet, so nobody touches a
router. Each player installs the same app and joins the same network; the joiners then use the
host's address **inside that network**. Windows Firewall still applies (allow the game when it
asks).

- **Tailscale** ([tailscale.com/download](https://tailscale.com/download)): free for personal
  use. The host signs in and shares their machine or invites the others to their tailnet. The
  Tailscale app shows each machine's address, which starts with `100.`. Join with that.
- **ZeroTier** ([zerotier.com/download](https://www.zerotier.com/download/)): the host creates a
  network at [central.zerotier.com](https://central.zerotier.com) (accounts made before
  November 2025 use my.zerotier.com), sends the 16-character network ID to the others, and
  authorises each of them there once they join. The host's address is listed on that page.

Not verified: that ENet traffic gets through each of these without extra settings. Both carry
ordinary UDP, so it should; the first session will settle it.

## The other way: forward a port on the host's router

Only the host does this; joiners need nothing.

1. **Find the host's local address:** open a command prompt and run `ipconfig`; note the
   *IPv4 Address* of the adapter you use (it usually starts `192.168.` or `10.`).
2. **Forward the port:** open the router's admin page (often printed on the router), find
   *Port forwarding* (sometimes *Virtual server* or *NAT*), and forward **UDP 7777** to that
   local address. The steps differ per router; its manual has them.
3. **Allow it through Windows Firewall:** the first time you host, Windows asks whether Godot (or
   the game) may use the network. Allow it. If the network is marked *Public* in Windows, tick
   public networks too, or the prompt's choice will not cover it.
4. **Give friends your public address:** search the web for "what is my IP" on the host's PC and
   send that address. It can change when the router restarts.

## When it does not connect

The joiner sees "Could not reach ADDRESS:PORT." on the menu.

- **Game full:** a game holds four players (the host plus three; `create_server(port,
  MAX_PLAYERS - 1)` in `net.gd`), so a fifth is turned away. Not verified: what they see; most
  likely the same "Could not reach" message, since the game shows no "full" message of its own.

- **Firewall:** the host's Windows Firewall is blocking the game. Windows Security > Firewall &
  network protection > Allow an app through firewall: tick Godot (or the game) for the network
  type in use. A third-party antivirus may have its own firewall.
- **Wrong address:** over the internet, use the host's public address (port forward) or its
  virtual LAN address, never its `192.168.` one. Check for typos, and that both sides use the
  same port.
- **CGNAT:** if the WAN or internet address on the host's router page differs from what "what is
  my IP" shows, or starts with `100.64.` to `100.127.`, the internet provider shares one address
  among many customers and port forwarding cannot work. Use a virtual LAN.
- **Version mismatch:** everyone must run the same build. A mismatch may connect and then fail
  oddly (errors, missing players) instead of refusing; update everyone to the same version.
- **Host started after the joiner:** the host must be in the lobby before anyone presses Join.
- **Silent voice:** check the microphone permission above, and that you are holding **V**.

## Open items

- No exported build for friends yet: they need Godot 4.7 and a copy of the project. A Windows
  preset exists (`godot --path game --headless --export-release "Windows Desktop"` writes
  `build/`), but it doesn't pack the recorded sounds yet, so they fall back to stand-ins.
- The port cannot be set from the main menu, only with `--port=N`.
- Nothing checks that the host and joiners run the same version; a version handshake on connect
  would turn a mismatch into a clear message.
