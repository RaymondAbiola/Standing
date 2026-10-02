# Pitch video assets

`survey-dark.png` / `survey-light.png` (1920x1080) are the data frame for the
pitch video, shown from 0:00 to roughly 1:40 while the survey section is read.

Both are generated from `survey-frame.html`. To change a number or a label,
edit the `A` and `B` arrays in that file and re-shoot:

    google-chrome --headless=new --disable-gpu --hide-scrollbars \
      --window-size=1920,1080 --screenshot=survey-dark.png \
      "file://$PWD/survey-frame.html"

Numbers come from the 28 survey responses. Both panels share one horizontal
scale, so a bar length means the same thing on either side: that is what shows
bank transfer out-topping every blocker on the right.

Colours match the app. The mint is the app's accent, restated darker for the
light version because the dark mint scores 1.8:1 on white. Bars that are not
mint use a grey chosen to clear the accent by Delta E 30 in both modes, so the
highlight is not carried by colour alone for a colourblind viewer: the two
highlighted bars are also the ones named in the caption.
