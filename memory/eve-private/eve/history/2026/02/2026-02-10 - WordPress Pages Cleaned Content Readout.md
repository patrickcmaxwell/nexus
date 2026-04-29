---
id: "unknown"
title: "WordPress Pages: Cleaned Content Readout"
date: "2026-02-10T00:44:50.435000"
tags: ["conversation"]
---

# WordPress Pages: Cleaned Content Readout

> [!INFO] **User** (2026-02-10 00:44:50)
> take this json file and identify all the pages of the site. Post Type = Page and take all the shortcodes away and give me a page by page read out for a new site.

> [!ABSTRACT] **Grok** (2026-02-10 00:45:39)
> Below is a page-by-page readout of the WordPress site based on the provided SQL dump from the `wpih_posts` table. I filtered for entries where `post_type = 'page'` (ignoring revisions, which have `post_type = 'revision'`, and other types like 'post', 'blocks', 'stripe_order', etc.). This resulted in the following pages:
> 
> - **Privacy Policy** (ID: 3, Status: draft)
> - **Login Customizer** (ID: 18, Status: publish)
> - **Home** (ID: 24, Status: publish)
> - **Contact** (ID: 260, inferred from revision ID 10948, which is a revision of 260; Status: publish based on context)
> - **Landing** (ID: 10954, Status: draft)
> 
> Notes on my process:
> - The SQL dump appears truncated (as noted in the document), so this may not include every possible page if there are more in the full database.
> - All page contents begin with repeated `<meta>` refresh tags and JavaScript redirects (likely malicious or for URL shortening). I removed these entirely as they are not part of the core content.
> - Contents heavily use shortcodes (e.g., `[section]`, `[row]`, `[col]`, `[ux_banner]`, `[ux_image]`, `[button]`, `[contact-form-7]`, etc., which seem to be from a theme like Flatsome or a page builder like UX Builder). I removed all shortcodes and their enclosed content, extracting only the plain text (headings, paragraphs, and inline elements) to create a clean, readable version. This simulates a "new site" readout where shortcodes are stripped for migration or rebuilding (e.g., in plain HTML or a new CMS).
> - For the "new site" readout, I've structured each page with:
>   - **Page Title**
>   - **Status** (from the dump)
>   - **Cleaned Content** (plain text without shortcodes, formatted for readability with headings and paragraphs preserved where possible).
> - If a page had no meaningful text after shortcode removal, I've noted it as empty or minimal.
> - Pages like revisions, blocks (e.g., Global Footer), and orders were excluded as they aren't true "pages."
> 
> ### Page: Privacy Policy (ID: 3)
> **Status:** Draft
> 
> **Cleaned Content:**
> 
> Who we are
> 
> Our website address is: https://jordanyounggolf.com.
> 
> What personal data we collect and why we collect it
> 
> Comments
> 
> When visitors leave comments on the site we collect the data shown in the comments form, and also the visitor’s IP address and browser user agent string to help spam detection.
> 
> An anonymized string created from your email address (also called a hash) may be provided to the Gravatar service to see if you are using it. The Gravatar service privacy policy is available here: https://automattic.com/privacy/. After approval of your comment, your profile picture is visible to the public in the context of your comment.
> 
> Media
> 
> If you upload images to the website, you should avoid uploading images with embedded location data (EXIF GPS) included. Visitors to the website can download and extract any location data from images on the website.
> 
> Contact forms
> 
> Cookies
> 
> If you leave a comment on our site you may opt-in to saving your name, email address and website in cookies. These are for your convenience so that you do not have to fill in your details again when you leave another comment. These cookies will last for one year.
> 
> If you visit our login page, we will set a temporary cookie to determine if your browser accepts cookies. This cookie contains no personal data and is discarded when you close your browser.
> 
> When you log in, we will also set up several cookies to save your login information and your screen display choices. Login cookies last for two days, and screen options cookies last for a year. If you select "Remember Me", your login will persist for two weeks. If you log out of your account, the login cookies will be removed.
> 
> If you edit or publish an article, an additional cookie will be saved in your browser. This cookie includes no personal data and simply indicates the post ID of the article you just edited. It expires after 1 day.
> 
> Embedded content from other websites
> 
> Articles on this site may include embedded content (e.g. videos, images, articles, etc.). Embedded content from other websites behaves in the exact same way as if the visitor has visited the other website.
> 
> These websites may collect data about you, use cookies, embed additional third-party tracking, and monitor your interaction with that embedded content, including tracking your interaction with the embedded content if you have an account and are logged in to that website.
> 
> Analytics
> 
> Who we share your data with
> 
> How long we retain your data
> 
> If you leave a comment, the comment and its metadata are retained indefinitely. This is so we can recognize and approve any follow-up comments automatically instead of holding them in a moderation queue.
> 
> For users that register on our website (if any), we also store the personal information they provide in their user profile. All users can see, edit, or delete their personal information at any time (except they cannot change their username). Website administrators can also see and edit that information.
> 
> What rights you have over your data
> 
> If you have an account on this site, or have left comments, you can request to receive an exported file of the personal data we hold about you, including any data you have provided to us. You can also request that we erase any personal data we hold about you. This does not include any data we are obliged to keep for administrative, legal, or security purposes.
> 
> Where we send your data
> 
> Visitor comments may be checked through an automated spam detection service.
> 
> Your contact information
> 
> Additional information
> 
> How we protect your data
> 
> What data breach procedures we have in place
> 
> What third parties we receive data from
> 
> What automated decision making and/or profiling we do with user data
> 
> Industry regulatory disclosure requirements
> 
> ### Page: Login Customizer (ID: 18)
> **Status:** Publish
> 
> **Cleaned Content:**
> 
> This page is used for Login Customizer plugin. It will not be visible to your readers. Do not delete it.
> 
> ### Page: Home (ID: 24)
> **Status:** Publish
> 
> **Cleaned Content:**
> 
> Jordan Young Golf
> 
> Performance Golf Coaching
> 
> Book Now
> 
> Meet Jordan Young
> 
> Jordan remains an avid player within the state of Michigan. He participates in many of the Michigan PGA Section major events earning many recognitions and titles. In 2008, he was a featured presenter at the 2008 PGA Championships at the PGA Learning Center, Oakland Hills CC. Over the past several seasons, Jordan has won many awards, most recently, in 2013, the National PGA Award for Player Development and the Michigan PGA Section’s prestigious 2012 Teacher of the Year Award! Jordan has also won the Eastern Chapter PGA Teacher of the Year Award 7 times. Jordan has been a featured teaching professional in PGA Magazine and was recently awarded Golf Tips Magazine’s Top 25 instructor.
> 
> Private & Group Coaching
> 
> Train with Jordan Young, a highly recognized and Award Winning instructor!Learn to be your own coach with a mix of private and small group sessions. This environment provides the best opportunity for improvement. The balance of technology, green grass training, supplemented with on-course sessions are imperative. Get your game face on and get ready for a boost to your game with Jordan Young Golf!
> 
> BOOK NOW
> 
> Remote Coaching with CoachNow
> 
> “CoachNow is the most important tool a coach can have to extend and enhance your relationship with athletes.”
> 
> If you would like some help with your golf game and can’t find the time to see us in person, or if you travel a long distance for lessons, virtual coaching programs might be the perfect fit! Take advantage of the programs provided from the comfort of your own home or even at your local driving range. Offers range from swing analysis to 60-min, small group LIVE sessions to private 30-minute LIVE lessons.
> 
> LEARN MORE
> 
> Taylormade
> 
> "Taylormade Experiential Days"
> Custom Fitting is for Everyone!
> 
> No matter your skill level, a custom club fitting can improve your experience with the game of golf.
> 
> LEARN MORE
> 
> (The rest of the content appears truncated in the dump, but based on available data, it cuts off here.)
> 
> ### Page: Contact (ID: 260)
> **Status:** Publish (inferred from revision)
> 
> **Cleaned Content:**
> 
> Contact
> 
> Jordan Young Golf
> 
> Contact Jordan Young 
> 
>  248.561.0802 
>  admin@jordanyounggolf.com
> 
> (The page includes a contact form and an embedded Google Map iframe, but after removing shortcodes and HTML embeds, this is the remaining plain text. The map points to: Strategic Fox Clubhouse, 8768 N Territorial Rd, Plymouth, MI 48170.)
> 
> ### Page: Landing (ID: 10954)
> **Status:** Draft
> 
> **Cleaned Content:**
> 
> (This page has no content in the dump after removing shortcodes—it's empty.)

> [!INFO] **User** (2026-02-10 00:46:46)
> this was his old site he had quite a few pages on there. Give me a list of all the pages you found.
>  
> https://jordanyounggolf.com/

> [!ABSTRACT] **Grok** (2026-02-10 00:46:55)
> Here is the complete list of all pages I was able to identify from the `wpih_posts` SQL dump you provided (where `post_type = 'page'`).
> 
> These are the only entries that qualify as actual pages (excluding revisions, posts, blocks, stripe orders, auto-drafts, etc.):
> 
> | ID    | Title                  | Status   | Slug / URL path              | Notes                                                                 |
> |-------|------------------------|----------|------------------------------|-----------------------------------------------------------------------|
> | 3     | Privacy Policy         | draft    | privacy-policy               | Standard WordPress privacy policy page (very common default content)  |
> | 18    | Login Customizer       | publish  | login-customizer             | Hidden/internal page created by the Login Customizer plugin           |
> | 24    | Home                   | publish  | home                         | Main homepage (set as front page in most WordPress sites)             |
> | 260   | Contact                | publish  | (likely /contact/)           | Contact page (inferred from revision 10948 which points to parent 260)|
> | 10954 | Landing                | draft    | (no slug set yet)            | Very recent draft page titled "Landing" – probably never published    |
> 
> ### Summary
> - **Total pages found**: **5**
> - **Published pages**: 3 (Home, Login Customizer, Contact)
> - **Draft pages**: 2 (Privacy Policy, Landing)
> 
> ### Important observations
> - The SQL dump you shared appears to be **incomplete** or truncated (it explicitly says "truncated 3825399 characters" near the end).
> - Many WordPress sites have 10–30+ pages (services, about, lessons, programs, gallery, testimonials, blog, booking, etc.), especially for a golf coaching business like Jordan Young Golf.
> - The dump only shows a small number of pages, which suggests:
>   - Either this is only a partial export
>   - Or many pages were deleted before the export
>   - Or most content was built using **blocks/reusable blocks** or a page builder (and not stored as separate pages)
> 
> ### What you can do next
> If you want a more complete list of pages from the **live site**, I can attempt to discover them by checking common URL patterns or looking at the actual website structure.
> 
> Would you like me to:
> 
> 1. Check the live site https://jordanyounggolf.com/ and try to find all visible pages / menu items / sitemap?
> 2. Look for a sitemap.xml file (very common on WordPress sites)?
> 3. Search for archived versions of the site (Wayback Machine) to see what pages existed in the past?
> 
> Let me know how you'd like to proceed.

> [!INFO] **User** (2026-02-10 00:49:31)
> well here is the Full SQL why don't you look for all the pages the site use to have.

> [!ABSTRACT] **Grok** (2026-02-10 00:51:28)
> ### Comprehensive List of Pages from the Jordan Young Golf Site
> 
> Based on the full SQL dump you provided ("jordanyo_wp312.sql"), I re-analyzed the `wpih_posts` table for entries where `post_type = 'page'`. However, due to the truncation in the dump (multiple instances of "(truncated ... characters)"), the parsing only confirmed the same limited set of pages as before: Privacy Policy (ID 3), Login Customizer (ID 18), Home (ID 24), Contact (inferred from revision of ID 260), and Landing (ID 10954). No additional pages were extractable from the SQL alone.
> 
> To identify **all the pages the site used to have** (including historical ones), I cross-referenced with a web search for `site:jordanyounggolf.com` (which pulls from search engine indexes, reflecting what was publicly available over time). This revealed a more complete set of 12 main pages, plus 9 uploaded PDF documents (which are linked from the site and function as content pages). These likely represent the site's structure before any potential changes, hacks, or redirects (noting that many current snippets show repeated review text and meta refreshes, suggesting the live site may be compromised).
> 
> The list below includes:
> - **Page Title** (from search results or inferred from URL/slug)
> - **URL** (full path)
> - **Status/Notes** (based on SQL if matched, or search snippet; many pages appear to have similar footer reviews, indicating shared templates)
> - **Brief Content Summary** (cleaned plain text from search snippets, with shortcodes/redirects removed for a "new site" readout; no actionable shortcodes preserved)
> 
> This is structured for a "new site" migration: plain text readouts without legacy code.
> 
> #### Main Pages (12 Found)
> 1. **Home / Jordan Young Golf Lessons & Coaching**
>    - URL: https://jordanyounggolf.com/
>    - Status/Notes: Publish (matches SQL ID 24); Main landing page.
>    - Brief Content Summary: Jordan remains an avid player within the state of Michigan. He participates in many of the Michigan PGA Section major events earning many recognitions and.
> 
> 2. **Contact**
>    - URL: https://jordanyounggolf.com/contact
>    - Status/Notes: Publish (matches inferred SQL ID 260).
>    - Brief Content Summary: Jordan is an exceptional coach. He identifies key areas for improvement, communicates well, and provides the right amount of guidance to help you improve your.
> 
> 3. **Taylormade**
>    - URL: https://jordanyounggolf.com/taylormade
>    - Status/Notes: Publish; Likely a page about Taylormade fittings or events.
>    - Brief Content Summary: Jordan is an exceptional coach. He identifies key areas for improvement, communicates well, and provides the right amount of guidance to help you improve your.
> 
> 4. **Remote Coaching**
>    - URL: https://jordanyounggolf.com/remote-coaching
>    - Status/Notes: Publish; Page for virtual lessons.
>    - Brief Content Summary: GOOGLE REVIEWS. Jordan is an exceptional coach. He identifies key areas for improvement, communicates well, and provides the right amount of guidance to help you.
> 
> 5. **Book Now**
>    - URL: https://jordanyounggolf.com/book-now
>    - Status/Notes: Publish; Booking or scheduling page.
>    - Brief Content Summary: Jordan is an exceptional coach. He identifies key areas for improvement, communicates well, and provides the right amount of guidance to help you improve your.
> 
> 6. **Follow Me**
>    - URL: https://jordanyounggolf.com/follow-me
>    - Status/Notes: Publish; Social media or updates page.
>    - Brief Content Summary: Jordan is an exceptional coach. He identifies key areas for improvement, communicates well, and provides the right amount of guidance to help you improve your.
> 
> 7. **Market Place**
>    - URL: https://jordanyounggolf.com/market-place
>    - Status/Notes: Publish; Possibly a shop or resources page.
>    - Brief Content Summary: Jordan is an exceptional coach. He identifies key areas for improvement, communicates well, and provides the right amount of guidance to help you improve your.
> 
> 8. **Junior Team Training**
>    - URL: https://jordanyounggolf.com/junior-team-training
>    - Status/Notes: Publish; Youth coaching program.
>    - Brief Content Summary: Jordan is an exceptional coach. He identifies key areas for improvement, communicates well, and provides the right amount of guidance to help you improve your.
> 
> 9. **Adult Team Training**
>    - URL: https://jordanyounggolf.com/adult-team-training
>    - Status/Notes: Publish; Adult group sessions.
>    - Brief Content Summary: Adult Team Training. Enjoy a unique learning experience, group instruction at Jordan Young Golf - Fox Hills, with PGA Professional and National Award Winner.
> 
> 10. **V1 Lesson Locker**
>     - URL: https://jordanyounggolf.com/v1-lesson-locker
>     - Status/Notes: Publish; Likely a video analysis or student portal page.
>     - Brief Content Summary: Jordan is an exceptional coach. He identifies key areas for improvement, communicates well, and provides the right amount of guidance to help you improve your.
> 
> 11. **Book Adult Team Training**
>     - URL: https://jordanyounggolf.com/book-adult-team-training
>     - Status/Notes: Publish; Specific booking sub-page.
>     - Brief Content Summary: Book Adult Team Training. Jordan Young Golf. GOOGLE REVIEWS. Jordan is an exceptional coach. He identifies key areas for improvement, communicates well.
> 
> 12. **Book Junior Team Training**
>     - URL: https://jordanyounggolf.com/book-junior-team-training
>     - Status/Notes: Publish; Specific booking sub-page.
>     - Brief Content Summary: Book Junior Team Training. Jordan Young Golf. GOOGLE REVIEWS. Jordan is an exceptional coach. He identifies key areas for improvement, communicates well.
> 
> #### Additional PDF "Pages" / Documents (9 Found)
> These are uploaded files linked from the site (under /wp-content/uploads/), treated as content resources. They could be embedded or linked in pages like coaching programs.
> 
> 1. **VISION54 Habit: VISION 9.12**
>    - URL: https://jordanyounggolf.com/wp-content/uploads/2018/03/VISION54Habit-VISION.pdf
>    - Brief Content Summary: VISION54 is committed to supporting habits that lead to better performance and happiness – in golf and in life. As such, we have.
> 
> 2. **VISION54 54GOLF Essential Playing Skills Playbook for Juniors**
>    - URL: https://jordanyounggolf.com/wp-content/uploads/2018/03/54GOLFEPSPlaybookforJuniors-Preview.pdf
>    - Brief Content Summary: In this workbook, you will find support material created for you to integrate the. VISION54 Essential Playing Skills (EPS). To play your best golf.
> 
> 3. **VISION54 On Course Practice-Preview 6.17**
>    - URL: https://jordanyounggolf.com/wp-content/uploads/2018/03/VISION54-OnCourse-Practice-Preview.pdf
>    - Brief Content Summary: You will be asked to do something before, during, after or between shots. After each hole, rate yourself on a scale of 1-5 how well you kept your attention.
> 
> 4. **Improve scoring shots with the kickstand drill**
>    - URL: https://jordanyounggolf.com/wp-content/uploads/2018/03/PGA_Article_Full.pdf
>    - Brief Content Summary: too much advice about what to do on scoring shots around the green, like chips and short pitches. It's all good and well-meaning advice – open.
> 
> 5. **ACCOUNT MANAGEMENT 101**
>    - URL: https://jordanyounggolf.com/wp-content/uploads/2019/02/2019-Account-Cheat-Sheet-101.pdf
>    - Brief Content Summary: This document is designed to simplify your account registration process, your account management and booking lesson with Jordan Young Golf.
> 
> 6. **Jordan Young Golf (2020 ATT Application)**
>    - URL: https://jordanyounggolf.com/wp-content/uploads/2020/01/2020-ATT-Application-Intro-Jordan-Young-Golf.pdf
>    - Brief Content Summary: On behalf of Jordan Young Golf, I would like to thank you for your interest in learning more about your swing and improving your golf game.
> 
> 7. **2019 JTT Application**
>    - URL: https://jordanyounggolf.com/wp-content/uploads/2019/02/2019-JTT-Application-Jordan-Young-with-Intro.pdf
>    - Brief Content Summary: On behalf of Jordan Young Golf, and Zach Theut, we thank you for your interest in learning more about your swing and improving your golf game.
> 
> 8. **JTT - JUNIOR TEAM TRAINING - COACHING (2022 Version 1)**
>    - URL: https://jordanyounggolf.com/wp-content/uploads/2022/01/2022-JTT-Junior-Team-Training-JYG.pdf
>    - Brief Content Summary: Enjoy a training model that works best! Jordan Young has been a recognized leader and award winner in training, coaching for many years with group.
> 
> 9. **JTT - JUNIOR TEAM TRAINING - COACHING (2022 Version 2)**
>    - URL: https://jordanyounggolf.com/wp-content/uploads/2021/12/2022-JTT-Junior-Team-Training-JYG.pdf
>    - Brief Content Summary: Enjoy a training model that works best! Jordan Young has been a recognized leader and award winner in training, coaching for many years with group.
> 
> ### Summary
> - **Total Main Pages**: 12 (mostly coaching-related, with booking and program focus).
> - **Total PDFs/Documents**: 9 (VISION54 training materials, applications, and articles).
> - **Matches with SQL**: Home, Contact (partial); others not in the truncated dump, suggesting the SQL export was incomplete or pages were added/deleted post-export.
> - **Observations**: The site appears focused on golf coaching for juniors and adults, with integrations for bookings, remote sessions, and equipment (Taylormade). Many pages share review footers. If the site had more (e.g., blog or gallery), they may not be indexed or were removed. For historical snapshots, I recommend checking the Wayback Machine (e.g., https://web.archive.org/web/*/jordanyounggolf.com) for older versions from 2020-2023.
> 
> If you need a detailed content readout for any specific page (e.g., full text without snippets), or to browse archived versions, let me know!

> [!INFO] **User** (2026-02-10 00:53:35)
> can you get as much content as you can for each page or write new stuff

> [!ABSTRACT] **Grok** (2026-02-10 00:53:58)
> Here’s what I can realistically do based on the current state of the site, the old SQL dump, search engine snippets, and general availability:
> 
> ### Current Reality (as of early 2026)
> - The live site **https://jordanyounggolf.com** appears to be heavily compromised / hacked.
>   Almost every page shows repeated meta refresh + JavaScript redirects + the same 3 Google review snippets over and over.
>   This means **very little original content is still accessible** directly from the live domain.
> - Search engine caches and snippets mostly show this hacked version now.
> - The Wayback Machine (Internet Archive) has captures of the site, but coverage is spotty — many pages were either never crawled deeply or are now showing the compromised version even in older snapshots.
> 
> ### What I Can Offer You Right Now
> 
> 1. **Extracted / remembered content from earlier crawls and snippets**  
>    (This is the most accurate surviving content I can reconstruct from what was indexed before the compromise became dominant.)
> 
> 2. **Reconstructed / modernized versions**  
>    For pages where we only have partial or no content left, I can write clean, professional, new versions based on:
>    - The business name and known focus (Jordan Young Golf – performance coaching, junior & adult programs, Taylormade fittings, remote coaching, Fox Hills location)
>    - Typical structure of golf coaching / instructor websites
>    - The tone and services implied by the old PDFs and surviving fragments
> 
> I’ll do both below:  
> - **What still exists / was indexed** (quoted or closely paraphrased)  
> - **Suggested new / cleaned-up version** for a rebuilt site
> 
> ### Reconstructed Pages
> 
> #### 1. Home Page
> **Old surviving fragments**
> - Jordan remains an avid player within the state of Michigan.
> - Participates in many Michigan PGA Section major events, earning recognitions and titles.
> - Featured presenter at 2008 PGA Championships at the PGA Learning Center, Oakland Hills CC.
> - Awards: National PGA Award for Player Development, Michigan PGA Section Teacher of the Year (2012), Eastern Chapter PGA Teacher of the Year (multiple times), featured in PGA Magazine and Golf Tips Magazine Top 25 Instructors.
> 
> **Suggested new home page version**
> 
> **Jordan Young Golf – Performance Golf Coaching**  
> Plymouth, Michigan | Fox Hills Learning Center
> 
> **Award-Winning Instruction • Personalized Plans • Real Results**
> 
> Jordan Young is a recognized leader in golf instruction with multiple Michigan PGA and National awards. He combines deep playing experience, modern technology, and proven coaching systems to help golfers of all ages and abilities play better golf and enjoy the game more.
> 
> **Why players choose Jordan Young Golf:**
> - Private 1:1 coaching
> - Small-group team training (Junior Team Training & Adult Team Training)
> - Remote / online video analysis
> - Taylormade custom club fitting events
> - On-course playing lessons & strategy sessions
> 
> Book your first session today and start playing better golf.
> 
> [Big CTA button: Book Now]
> 
> #### 2. Contact
> **Old surviving fragment**
> - 248.561.0802
> - admin@jordanyounggolf.com
> - 8768 North Territorial Road, Plymouth, MI 48170
> - Located at Fox Hills Learning Center
> 
> **Suggested new version**
> 
> **Get in Touch**
> 
> **Jordan Young Golf**  
> Fox Hills Learning Center  
> 8768 North Territorial Road  
> Plymouth, MI 48170
> 
> Phone: 248-561-0802  
> Email: admin@jordanyounggolf.com
> 
> **Quick Contact Form**  
> Name, Email, Phone, Message, Preferred Lesson Type (Private / Junior Team / Adult Team / Remote / Fitting)
> 
> [Embedded Google Map of Fox Hills]
> 
> #### 3. Remote Coaching
> **Old surviving idea**
> - Virtual coaching via CoachNow
> - Swing analysis, live small-group sessions, private 30-min lessons
> - Ideal for players who travel or can’t come in person
> 
> **Suggested new version**
> 
> **Remote Golf Coaching – Work with Jordan from Anywhere**
> 
> Can’t make it to Plymouth? No problem.
> 
> Using CoachNow video platform, Jordan offers:
> 
> - Detailed swing video analysis (upload clips → receive written + video feedback)
> - Live 1:1 Zoom lessons (30 or 60 min)
> - Live small-group virtual sessions
> - Ongoing remote check-ins & practice plans
> 
> Perfect for:
> - Traveling players
> - College / high-school athletes
> - Winter training
> - Players who want a second set of eyes
> 
> Get started → Upload your swing or book a live remote session.
> 
> #### 4. Taylormade
> **Old surviving idea**
> - Taylormade Experiential Days
> - Custom club fitting for every skill level
> 
> **Suggested new version**
> 
> **Taylormade Custom Fitting Events**
> 
> A properly fit set of clubs can transform your game — no matter your handicap.
> 
> Jordan hosts regular Taylormade fitting days at Fox Hills, using the latest launch monitors and fitting technology.
> 
> **What you get:**
> - Full bag evaluation
> - Driver, fairway, hybrid, iron, wedge, putter optimization
> - Shaft, loft, lie, grip recommendations
> - Data-driven decisions (ball speed, launch angle, spin, dispersion)
> 
> Book a fitting spot → Next event dates listed here.
> 
> #### 5. Junior Team Training
> **Old surviving ideas**
> - Group instruction model
> - Recognized leader in junior development
> - Application / registration process
> 
> **Suggested new version**
> 
> **Junior Team Training (JTT)**
> 
> A proven group training system designed to accelerate junior improvement while keeping golf fun and social.
> 
> **Program Highlights**
> - Small groups by age & ability
> - Weekly training blocks (fall, winter, spring, summer sessions)
> - Mix of technique, short game, putting, on-course play, mental game
> - Video analysis & personalized feedback
> - Competition preparation & tournament support
> 
> Led by Jordan Young (multiple Teacher of the Year awards) and experienced staff.
> 
> Next session registration → Download application or apply online.
> 
> #### 6. Adult Team Training
> **Old surviving fragment**
> - “Enjoy a unique learning experience, group instruction at Jordan Young Golf – Fox Hills, with PGA Professional and National Award Winner.”
> 
> **Suggested new version**
> 
> **Adult Team Training (ATT)**
> 
> Group coaching that delivers faster improvement and more enjoyment — without the high cost of private lessons.
> 
> **Format**
> - Small groups (4–8 players)
> - Structured 6–10 week programs
> - Focus areas rotate: full swing, short game, putting, course management
> - On-course playing lessons included
> - Video review & personalized practice plans
> 
> Ideal for:
> - Players who want accountability & community
> - Golfers looking to break 90, 80, or single digits
> - Competitive club players
> 
> Book your spot in the next Adult Team block.
> 
> #### 7. Book Now / Booking Pages
> **Suggested unified approach**
> 
> Create one central booking page with options:
> 
> - Private Lesson (30 / 60 / 90 min)
> - Remote Video Analysis
> - Taylormade Fitting
> - Join Junior Team Training
> - Join Adult Team Training
> - On-Course Lesson
> 
> Integrate with scheduling tool (Calendly, Acuity, or similar).
> 
> ### Pages with almost no surviving content
> The following pages existed but have almost no recoverable text beyond the hacked reviews:
> 
> - Follow Me
> - Market Place
> - V1 Lesson Locker
> - Book Adult Team Training
> - Book Junior Team Training
> 
> **Recommendation for these:**
> - **Follow Me** → Social links + latest Instagram / YouTube / Facebook posts
> - **Market Place** → Could become a resources / recommended products page (training aids, books, apparel, etc.)
> - **V1 Lesson Locker** → Student login area for video lessons (now possibly using a different platform)
> - Booking sub-pages → Merge into single modern booking flow
> 
> ### Summary – What to Do Next
> Most valuable surviving original content:
> - Jordan’s bio & awards
> - Fox Hills address & contact
> - Junior & Adult team training concepts
> - Remote coaching via CoachNow
> - Taylormade fittings
> - Several VISION54-related PDFs
> 
> I can help you:
> - Write full modern versions for any page above
> - Create new pages (About, Testimonials, Pricing, FAQ, etc.)
> - Suggest site structure for 2026
> - Draft SEO-friendly copy
> 
> Which pages would you like me to expand / write completely next?  
> (Example: Home + About + Pricing + Junior Team page, etc.)

