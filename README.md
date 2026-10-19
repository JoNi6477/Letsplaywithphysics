# Let's Play With Physics

Website for **letsplaywithphysics.in** — NEET & JEE Mains physics coaching by Akshay Sir.

## How the repository is organised

```
letsplaywithphysics/
│
├── index.html            Home page
├── course.html           Courses (video lectures — coming soon)
├── material.html         Study Materials (asks visitors to log in)
├── simulations.html      Simulations list
├── mocktest.html         Mock test (NTA exam screen — login + plan required)
├── login.html            Log in / create account / forgot password
├── reset-password.html   Set a new password (from the email link)
├── dashboard.html        Student portal (after login)
├── admin.html            Admin panel (Akshay Sir only)
├── about.html, contact.html, privacy-policy.html, terms.html
│
├── materials/            All PDFs students can open
│   ├── formula-sheets/
│   │   ├── neet/
│   │   └── jee/
│   ├── practice-questions/
│   │   ├── neet/
│   │   └── jee/
│   ├── notes/            Quick revision notes
│   └── archive/          Old versions — not shown on the website
│
├── simulations/          Interactive simulation pages
├── images/               Logo (full + menu-bar size) and browser-tab icon
├── css/                  Styles for the login, portal and admin pages
├── js/                   Shared scripts
│   ├── materials-data.js   ← list of every study material and simulation
│   ├── supabase-config.js  Supabase connection (publishable key only)
│   ├── account.js          Login helpers
│   └── nav-account.js      Shows "Login" / "My Account" in the menu
│
├── supabase/             Database setup (run once in Supabase → SQL Editor)
│   ├── schema.sql          Student accounts, plans, access
│   ├── mock-tests.sql      Protected mock tests, questions, results
│   └── SETUP.md            Step-by-step setup guide
│
└── CNAME, ads.txt, google…html   Needed by GitHub Pages / Google — don't move
```

> Website pages (`*.html`) must stay in the top folder — moving them would change their web addresses.

## How to add a study material

1. Name the PDF in lowercase with dashes, e.g. `current-electricity.pdf`.
2. On GitHub open the right folder, e.g. `materials/formula-sheets/jee/`,
   then **Add file → Upload files** → **Commit changes**.
3. Open `js/materials-data.js`, find the right list (`"NEET"` or `"JEE Mains"`
   under the right section) and add one line:

   ```js
   { "title": "Current Electricity — Formula Sheet", "file": "materials/formula-sheets/jee/current-electricity.pdf", "isNew": true },
   ```

It then appears in the student portal → **Study Materials**.

## How to add a simulation

1. Upload the simulation's HTML file into `simulations/`.
2. Add a card for it in `simulations.html`, and a line to the `SIMULATIONS`
   list at the bottom of `js/materials-data.js`.

## Mock tests, students and plans

Questions, answers, student accounts, plans and results are stored in
**Supabase** (not in this repository). See [`supabase/SETUP.md`](supabase/SETUP.md).
Give students access from the **Admin panel** on the website.
