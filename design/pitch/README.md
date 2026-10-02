# Pitch video assets

Two 1920x1080 frames. Both are generated from HTML, so edit the HTML and
re-shoot rather than touching the PNGs.

| File | Used at | Shows |
|---|---|---|
| `survey-frame.html` / `survey-dark.png` / `survey-light.png` | 0:00 to 1:40 | the two survey findings |
| `close-frame.html` / `close-dark.png` | 3:32 to 3:50 | logo, live URL, contact |

## Recording

This display is exactly 1920x1080, so open the HTML in the browser and press
F11. Fullscreen gives a pixel-for-pixel frame with no viewer chrome, no
letterboxing and no address bar. The PNGs are only a fallback for recording on
another machine.

    google-chrome design/pitch/survey-frame.html    # then F11

Use F11 for the app sections too, so no tabs or URL bar end up in the video.

## Before recording

`close-frame.html` has two placeholders that must be replaced:

    REPLACE-WITH-LIVE-URL
    REPLACE-WITH-CONTACT

## Re-shooting

    google-chrome --headless=new --disable-gpu --hide-scrollbars \
      --window-size=1920,1080 --screenshot=close-dark.png \
      "file://$PWD/close-frame.html"

## Notes on the survey frame

Numbers come from the 28 survey responses. Both panels share one horizontal
scale, so a bar length means the same thing on either side: that is what shows
bank transfer out-topping every blocker on the right. The right panel is in the
order respondents ranked it, not reordered, so the two highlighted bars are
first and third.

Colours match the app. The mint is restated darker in the light version because
the dark mint scores 1.8:1 on white. Non-highlighted bars use a grey that clears
the accent by Delta E 30 in both modes, and the highlight is named in the
caption so it never depends on colour alone.
