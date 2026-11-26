// Play Store screenshots: caption + which text in each phone screenshot to replace with sample data.
// Coordinates are in the original 717 x 1600 screenshot. Files named 01-08 are the 8 to upload
// (Play allows 8 phone screenshots); extra-* are spares.
//
// Text overlay: `region` is a loose box around the original text; the page finds the exact text,
// covers it with the background colour and draws `text` in the same font at the same size
// (worked out from `orig`, the text being replaced).
//   font:      CSS font without the size, e.g. "700 'Space Mono'" (from the app's AppTheme)
//   size:      fixed size in px instead of measuring; ls: letter spacing in px, or 'auto'; default 0
//   align:     'left' (default), 'center' or 'right'
//   patch:     box to cover when it is bigger than the text used for sizing (e.g. emoji after a name)
//   after:     id of an earlier overlay: start after its new text, keeping the original gap
//   cont:      id of an earlier overlay: continue straight after it, same font and line (colorFrom: box)
//   threshold: how different from the background a pixel must be to count as text (default 90)
// Other steps: { type: 'rect', box, color }  { type: 'copy', from, to }  { type: 'cut', y0, y1, end, fillFrom, color }
//   color [x, y] = the colour of that pixel in the original.
(() => {
  const MONO = "700 'Space Mono'", BODY = "700 'Archivo'", ANTON = "400 'Anton'";
  // Team leader header: name under the title and the initial in the round avatar.
  const tlHeader = (nameY, avatarY) => [
    { region: [25, nameY - 10, 140, nameY + 10], orig: 'TEST', text: 'PRIYA', font: MONO },
    { region: [584, avatarY - 16, 611, avatarY + 16], orig: 'T', text: 'P', font: ANTON, align: 'center' },
  ];
  // emoji = [x where the emoji start, x where the line ends]: size from the text before it, cover both.
  const leadCard = (nameY, phoneY, name, newName, phone, newPhone, emoji) => [
    emoji
      ? { region: [55, nameY - 22, emoji[0], nameY + 22], patch: [55, nameY - 24, emoji[1], nameY + 24], orig: name, text: newName, font: BODY }
      : { region: [55, nameY - 22, 468, nameY + 22], orig: name, text: newName, font: BODY },
    { region: [55, phoneY - 13, 470, phoneY + 13], orig: phone, text: newPhone, font: MONO },
  ];
  const chip = (y, x0, x1, orig, text) => ({ region: [x0, y - 11, x1, y + 11], orig, text, font: MONO, align: 'center' });
  // Caller "My leads" card: name at x 65 (tag at x 446), phone line 39 px lower.
  const myLead = (nameY, name, newName, phone, newPhone, emoji) => [
    emoji
      ? { region: [55, nameY - 20, emoji[0], nameY + 20], patch: [55, nameY - 22, emoji[1], nameY + 22], orig: name, text: newName, font: BODY }
      : { region: [55, nameY - 20, 440, nameY + 20], orig: name, text: newName, font: BODY },
    { region: [55, nameY + 27, 440, nameY + 51], orig: phone, text: newPhone, font: MONO },
    chip(nameY, 452, 530, 'KABILAN', 'ARUN'),
  ];
  // Call log card: name at x 154, number 67 px lower.
  const logCard = (y, name, newName, phone, newPhone, emoji) => [
    emoji
      ? { region: [148, y - 18, emoji[0], y + 18], patch: [148, y - 20, emoji[1], y + 20], orig: name, text: newName, font: BODY }
      : { region: [148, y - 18, 470, y + 18], orig: name, text: newName, font: BODY },
    { region: [148, y + 56, 340, y + 78], orig: phone, text: newPhone, font: MONO },
  ];
  // Sample contacts used across the call screens (real names and numbers replaced).
  const C = {
    siva: ['Sivakumar A', 'Deepa Foods', '+919944446953', '+919876500905'],
    surya: ['Surya 2', 'Vignesh Motors', '+917092975131', '+919876500784'],
    vick: ['Vick Bro Senior', 'Suresh Traders', '+919786742563', '+919876500218'],
    ponka: ['Ponkarathiri Mam', 'Priya Textiles', '+919894446064', '+919876500342'],
    appa: ['Appa', 'Lakshmi Stores', '+919788692699', '+919876500563'],
    madhan: ['Madhan Askeva', 'Anand Electricals', '+919025614585', '+919876500436'],
    rajesh: ['RAJESH ARUNACHAL...', 'BALAJI AGENCIES', '+917550304003', '+919876500657'],
    dinesh: ['Dinesh Pandi Intern', 'Kavya Fashions', '+918438809244', '+919876500129'],
    sakthi: ['Sakthivel', 'Meena Silks', '+918056555017', '+919876500871'],
    akka: ['Akka', 'Ravi Kumar', '8838777709', '9876500994'],
    mother: ['Mother', 'Selvam Hardware', '8056620329', '9876500615'],
  };
  const log = (y, c, emoji) => logCard(y, c[0], c[1], c[2], c[3], emoji);

  window.SHOTS = {
    home: {
      image: 'home', file: '01-home',
      eyebrow: 'For callers', caps: 'Your day,', accent: 'at a glance', sub: 'Daily target, talk time and every call type in one place.',
      overlays: [
        { region: [28, 98, 405, 168], orig: 'HELLO, KABILAN.', text: 'HELLO, ARUN.', font: ANTON },
        { region: [622, 96, 660, 138], orig: 'K', text: 'A', font: ANTON, align: 'center' },
        { id: 'tgt', region: [62, 520, 280, 608], orig: '0/250', text: '186', font: ANTON, color: '#FFFFFF' },
        { id: 'tgt2', cont: 'tgt', text: '/250', colorFrom: [150, 520, 280, 608] },
        { region: [284, 576, 425, 610], orig: 'calls today', text: 'calls today', font: "500 'Archivo'", threshold: 40, after: 'tgt2' },
        { region: [58, 772, 115, 842], orig: '0', text: '142', font: ANTON },
        { region: [395, 772, 485, 842], orig: '0s', text: '6h 12m', font: ANTON },
        { region: [84, 1016, 114, 1054], orig: '0', text: '186', font: ANTON },
        { region: [248, 1016, 278, 1054], orig: '0', text: '28', font: ANTON },
        { region: [390, 1016, 420, 1054], orig: '0', text: '158', font: ANTON },
        { region: [536, 1016, 566, 1054], orig: '0', text: '9', font: ANTON },
        { region: [84, 1121, 114, 1159], orig: '0', text: '3', font: ANTON },
        { region: [228, 1121, 258, 1159], orig: '0', text: '4', font: ANTON },
        { region: [428, 1121, 458, 1159], orig: '0', text: '128', font: ANTON },
        { region: [55, 1286, 120, 1340], orig: '0s', text: '18m 42s', font: ANTON },
        { region: [55, 1342, 200, 1370], orig: 'No calls yet', text: 'Lakshmi Stores', font: "400 'Archivo'" },
        { region: [392, 1286, 555, 1340], orig: '0x calls', text: '6x calls', font: ANTON },
        { region: [392, 1342, 575, 1370], orig: 'No repeated calls', text: 'Karthik Enterprises', font: "400 'Archivo'" },
        // Drop the red "Calls are not being recorded" banner; the cards below move up.
        { type: 'cut', y0: 262, y1: 441, end: 1455, fillFrom: 1228, color: [15, 700] },
      ],
    },
    'my-leads': {
      image: 'my-leads', file: '02-my-leads',
      eyebrow: 'For callers', caps: 'Dial leads', accent: 'in one tap', sub: 'Your assigned leads, ready to call.',
      overlays: [
        // Remove the floating call bubble over the search bar, then redraw the placeholder text.
        { type: 'copy', from: [406, 100, 496, 172], to: [314, 100] },     // clean strip of paper + bar border
        { type: 'rect', box: [314, 173, 406, 214], color: [600, 215] },
        { region: [125, 172, 316, 208], orig: 'Search lead or p', text: 'Search lead or phone...', font: "400 'Archivo'" },
        ...myLead(443, C.siva[0], C.siva[1], '+919944446953 · 7× dialed', '+919876500905 · 7× dialed'),
        ...myLead(680, C.surya[0], C.surya[1], '+917092975131 · 6× dialed', '+919876500784 · 6× dialed'),
        ...myLead(916, C.vick[0], C.vick[1], '+919786742563 · 1× dialed', '+919876500218 · 1× dialed'),
        ...myLead(1153, C.ponka[0], C.ponka[1], '+919894446064 · 2× dialed', '+919876500342 · 2× dialed'),
        ...myLead(1389, 'Appa', 'Lakshmi Stores', '+919788692699 · 4× dialed', '+919876500563 · 4× dialed', [138, 215]),
      ],
    },
    'call-log-all': {
      image: 'call-log-all', file: '03-call-log',
      eyebrow: 'For callers', caps: 'Every call,', accent: 'logged', sub: 'Incoming, outgoing and missed calls on your work SIM.',
      overlays: [
        ...log(481, C.siva), ...log(632, C.surya), ...log(784, C.vick),
        ...log(987, C.surya), ...log(1139, C.ponka), ...log(1290, C.ponka),
        { type: 'rect', box: [222, 1419, 300, 1433], color: [200, 1427] },   // emoji peeking from the next card
      ],
    },
    keypad: {
      image: 'keypad', file: 'extra-keypad',
      eyebrow: 'For callers', caps: 'Dial any', accent: 'number', sub: 'A keypad for work calls on your work SIM.',
      overlays: [
        { type: 'rect', box: [38, 256, 682, 342], color: [20, 300] },        // "Calls open in your phone's call screen" prompt
      ],
    },
    'call-log-missed': {
      image: 'call-log-missed', file: 'extra-call-log-missed',
      eyebrow: 'For callers', caps: 'Missed calls,', accent: 'sorted', sub: 'See who called and call back in one tap.',
      overlays: [
        ...log(481, C.ponka), ...log(632, C.madhan), ...log(784, C.appa, [222, 300]), ...log(936, C.madhan),
        ...log(1139, C.surya), ...log(1290, C.rajesh),
      ],
    },
    'call-log-incoming': {
      image: 'call-log-incoming', file: 'extra-call-log-incoming',
      eyebrow: 'For callers', caps: 'Know who', accent: 'called', sub: 'Every incoming call with its time and length.',
      overlays: [
        ...log(481, C.siva), ...log(632, C.surya), ...log(784, C.vick),
        ...log(987, C.surya), ...log(1139, C.appa, [222, 300]), ...log(1290, C.dinesh),
      ],
    },
    'call-log-outgoing': {
      image: 'call-log-outgoing', file: 'extra-call-log-outgoing',
      eyebrow: 'For callers', caps: 'Calls made,', accent: 'counted', sub: 'Talk time for every call you make.',
      overlays: [
        ...log(481, C.ponka), ...log(632, C.sakthi), ...log(784, C.sakthi), ...log(936, C.akka),
        ...log(1088, C.appa, [222, 300]), ...log(1239, C.mother, [241, 312]),
        { region: [148, 1375, 470, 1409], orig: 'Rajesh (Mama)', text: 'Arjun Builders', font: BODY },
      ],
    },
    'book-demo': {
      image: 'book-demo', file: '04-book-demo',
      eyebrow: 'For callers', caps: 'Book demos,', accent: 'fast', sub: 'Pick a team leader, a date and a free slot.',
      overlays: [
        chip(294, 68, 182, 'BHAVANI', 'DEEPIKA'),
        chip(294, 223, 414, 'DHANA SEKARAN', 'RAMESH KUMAR'),
        chip(294, 454, 594, 'KALAIVANI', 'MEENAKSHI'),
        chip(374, 68, 182, 'PRAVEEN', 'KARTHIK'),
        chip(374, 223, 298, 'TEST', 'PRIYA'),
      ],
    },
    dashboard: {
      image: 'dashboard', file: '05-team-dashboard',
      eyebrow: 'For team leaders', caps: 'Team calls,', accent: 'live', sub: 'Calls, talk time and connect rate as they happen.',
      overlays: [
        ...tlHeader(119, 101),
        { id: 'big', region: [55, 612, 126, 722], orig: '0', text: '186', font: ANTON },
        { region: [130, 668, 262, 724], orig: '0s talk', text: '6h 12m talk', font: "italic 500 'Playfair Display'", after: 'big' },
        { region: [55, 728, 480, 762], orig: '0 connected · 0 unique clients · target 250', text: '142 connected · 128 unique clients · target 250', font: "500 'Archivo'", threshold: 40 },
        { region: [50, 902, 140, 964], orig: '0s', text: '2m 37s', font: ANTON },
        { region: [390, 902, 530, 964], orig: '0.0%', text: '76.3%', font: ANTON },
        { region: [390, 962, 560, 990], orig: '0 of 0 picked', text: '142 of 186 picked', font: "500 'Archivo'" },
        { region: [50, 1090, 110, 1152], orig: '0', text: '158', font: ANTON },
        { region: [390, 1090, 450, 1152], orig: '0', text: '28', font: ANTON },
        { region: [50, 1248, 110, 1310], orig: '0', text: '9', font: ANTON },
        { region: [390, 1248, 450, 1310], orig: '0', text: '4', font: ANTON },
      ],
    },
    leads: {
      image: 'leads', file: '06-team-leads',
      eyebrow: 'For team leaders', caps: 'Every lead,', accent: 'tracked', sub: "Each lead's status and call history at a glance.",
      overlays: [
        ...leadCard(452, 491, 'Siva Project Coordinator As...', 'Karthik Enterprises', '+917358432111 · 256× dialed', '+919876500121 · 6× dialed'),
        ...leadCard(689, 729, 'Kiruthick Intern', 'Priya Textiles', '6380494647 · 32× dialed', '+919876500342 · 4× dialed'),
        ...leadCard(925, 966, 'Mother', 'Lakshmi Stores', '+918056620329 · 31× dialed', '+919876500563 · 3× dialed', [154, 468]),
        ...leadCard(1164, 1204, 'Surya Clg', 'Vignesh Motors', '9342073851 · 7× dialed', '+919876500784 · 5× dialed', [190, 468]),
        { region: [55, 1380, 468, 1424], orig: 'Sivakumar A', text: 'Deepa Foods', font: BODY },
        { region: [55, 1429, 470, 1452], orig: '+919944446953 · 68× dialed', text: '+919876500905 · 2× dialed', font: MONO },
        chip(453, 481, 560, 'KABILAN', 'ARUN'),
        chip(690, 481, 560, 'KABILAN', 'ARUN'),
        chip(927, 481, 560, 'KABILAN', 'ARUN'),
        chip(1165, 481, 560, 'KABILAN', 'ARUN'),
        chip(1403, 481, 560, 'KABILAN', 'ARUN'),
      ],
    },
    recordings: {
      image: 'recordings', file: '07-recordings',
      eyebrow: 'For team leaders', caps: 'Rate every', accent: 'call', sub: 'Play recordings, rate quality and leave feedback.',
      overlays: [
        ...tlHeader(127, 104),
        { region: [55, 392, 134, 422], orig: 'kabilan', text: 'karthik', font: BODY },
        { region: [158, 390, 380, 424], orig: '+919384090017', text: '+919876500121', font: "600 'Archivo'" },
        { region: [55, 810, 134, 840], orig: 'kabilan', text: 'karthik', font: BODY },
        { region: [158, 808, 380, 842], orig: '+919944446953', text: '+919876500342', font: "600 'Archivo'" },
        { region: [55, 1229, 134, 1259], orig: 'kabilan', text: 'karthik', font: BODY },
        { region: [158, 1226, 330, 1262], orig: 'Sakthivel', text: 'Lakshmi Stores', font: "600 'Archivo'" },
      ],
    },
    leaderboard: {
      image: 'leaderboard', file: '08-leaderboard',
      eyebrow: 'For team leaders', caps: 'Top callers,', accent: 'ranked', sub: 'Rank your team by talk time: today, this week or month.',
      overlays: [
        ...tlHeader(127, 104),
        { region: [270, 530, 385, 562], orig: 'kabilan', text: 'karthik', font: BODY },
        { region: [228, 568, 530, 597], orig: '0/100 calls (0% conn) · 0 conn', text: '86/100 calls (78% conn) · 67 conn', font: "500 'Archivo'", threshold: 40 },
        { region: [600, 542, 672, 577], orig: '0m', text: '3h 42m', font: MONO, align: 'right' },
      ],
    },
    profile: {
      image: 'profile', file: 'extra-profile',
      eyebrow: 'For team leaders', caps: 'Everything in', accent: 'one place', sub: 'Reports, the web portal and recording status.',
      overlays: [
        ...tlHeader(127, 104),
        { region: [92, 226, 130, 278], orig: 'T', text: 'P', font: ANTON, align: 'center' },
        { region: [184, 200, 300, 236], orig: 'TEST', text: 'PRIYA', font: BODY },
      ],
    },
    'profile-menu': {
      image: 'profile-menu', file: 'extra-profile-menu',
      eyebrow: 'For everyone', caps: 'Set up in', accent: 'minutes', sub: 'Profile, call recording setup and permissions in one menu.',
      overlays: [
        ...tlHeader(127, 104),
        { region: [92, 226, 130, 278], orig: 'T', text: 'P', font: ANTON, align: 'center' },
        { region: [184, 200, 300, 236], orig: 'TEST', text: 'PRIYA', font: BODY, threshold: 50 },
        { region: [94, 566, 126, 614], orig: 'T', text: 'P', font: ANTON, align: 'center' },
        { region: [170, 556, 240, 594], orig: 'TEST', text: 'PRIYA', font: ANTON },
        { region: [170, 596, 610, 621], orig: '8148909412 · ACTIVE WORK SIM: airtel', text: '9876500777 · ACTIVE WORK SIM: airtel', font: MONO },
      ],
    },
  };
})();
