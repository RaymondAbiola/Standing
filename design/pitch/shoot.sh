#!/bin/bash
cd "$(dirname "$0")"
shot() {
  google-chrome --headless=new --disable-gpu --no-sandbox --hide-scrollbars \
    --force-device-scale-factor=1 --window-size=1920,1080 \
    --screenshot="$2" "file://$PWD/$1" 2>/dev/null
}
shot survey-frame.html survey-dark.png
shot close-frame.html  close-dark.png
sed 's|<body>|<body><script>document.documentElement.setAttribute("data-theme","light")</script>|' \
  survey-frame.html > .light.html
shot .light.html survey-light.png
rm -f .light.html
