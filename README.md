<p align="center">
  <img src="assets/icon.png" width="120" alt="Boogie app icon">
</p>

<h1 align="center">boogie.</h1>
<p align="center">A little company for your desktop.</p>

Give your Mac a little dance party. Boogie brings tiny dancers to your desktop
to keep you company while you work, study, or take a break.

Pick a favorite. Bring the whole crew. Click someone and watch the hearts fly.

## Your desktop, your dance floor

- **Meet the crew.** Sophia, Manuel, Carla, and Nathan are ready to dance. Prefer a retro look? Try the **Pixel classics**.
- **Invite as many as you like.** Go **Solo**, **Duo**, or **Trio**, or choose **Custom** to pick everyone yourself. Mix your favorites and use **+ / −** to add or remove copies. Boogie remembers your lineup.
- **Find your mood.** Keep it easy, turn up the pace, or let Boogie shuffle through the dances. Make your dancers tiny or give them more room to shine.
- **Play a little.** Click a dancer for a jump and hearts. Drag them around and watch them land back at the bottom of your screen.
- **Take a breather.** Pause or hide everyone whenever you like. They'll be there when you're ready.

On supported MacBooks, the crew can also slide when you tilt your Mac, duck when
you lower the lid, and glow when the room gets dark. Turn these on or off in **Preferences**.

<details>
  <summary>Take a peek at the controls</summary>
  <p align="center">
    <img src="assets/panel.png" width="380" alt="Choose your dancers, build a lineup, and set the mood in Boogie">
  </p>
</details>

## Get Boogie

You'll need a Mac running **macOS Ventura (13) or later**. Choose whichever
installation method feels more comfortable.

### Option 1: Let your AI assistant install it

Already use **Codex**, **Claude Code**, or another coding assistant that can run
commands on your Mac? Copy and paste this prompt into it:

```text
Install Boogie on my Mac from https://github.com/pratikaman/Boogie.

Check the requirements and help me install anything missing. Download the
project, run ./build.sh --install, and open ~/Applications/Boogie.app.

If I already have Boogie, keep my saved dancers and settings. Don't overwrite
any local project changes. Tell me when it's ready and how to open the controls.
```

Follow any installation steps your assistant shows you. Once Boogie opens,
look for the little dancer icon in the menu bar at the top of your screen.

### Option 2: Install with commands

Open **Terminal** on your Mac. You can find it by pressing **⌘ Space** and typing
“Terminal.”

First, install Apple's command line tools if you don't already have them:

```sh
xcode-select --install
```

Finish the installer before continuing. If Terminal says the tools are already
installed, you're ready for the next step.

Then copy and run these commands:

```sh
git clone https://github.com/pratikaman/Boogie.git &&
cd Boogie &&
./build.sh --install &&
open "$HOME/Applications/Boogie.app"
```

Give it a few minutes. Boogie will be installed in your home folder's
**Applications** folder and open when it's ready.

**Want to create a dancer from a photo?** That optional feature also needs Codex
installed and signed in on your Mac, with image generation available. The dancers
that come with Boogie are ready to use without it.

## Your first dance

1. Click the **Boogie icon in the menu bar**, or right-click a dancer, to open the controls.
2. Choose your dancers, their size, and a pace you like.
3. Enjoy the company. Use **Return to Dock** whenever you want everyone back together.

Want the crew to greet you every day? Turn on **Launch at login** in **Preferences**.

## Put yourself on the dance floor

Choose **Create a dancer** and pick a clear photo of yourself. A photo showing
your face and whole outfit works best.

Click **Generate likeness** and check the result. Once you're happy with it,
choose **Make 8-pose preview**, give your dancer a name, and click **Add to my dancers**.
You can mix your new dancer into any custom lineup.

Photo dances are simple pose loops, so they won't move as smoothly as the dancers
that come with Boogie. Already have a smooth dance video? Choose **Import smooth
dance video…** and try a short, looping clip of one person, with their whole body
visible. Clips should be 1–8 seconds long. Boogie removes the background for you.

Making a dancer from a photo sends that photo to OpenAI through your Codex account.
Imported videos are processed on your Mac. Once saved, your dancers can keep
dancing offline.

---

Characters by [Renderpeople](https://renderpeople.com/free-3d-people/).
[Character credits](assets/CHARACTERS.md) · [Want to contribute?](CONTRIBUTING.md)
