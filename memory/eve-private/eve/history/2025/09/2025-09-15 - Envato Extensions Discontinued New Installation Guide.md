---
id: "unknown"
title: "Envato Extensions Discontinued: New Installation Guide"
date: "2025-09-15T19:22:13.525000"
tags: ["conversation"]
---

# Envato Extensions Discontinued: New Installation Guide

> [!INFO] **User** (2025-09-15 19:22:13)
> I tried using envato to install a template kit for elementor and it is giving me a warning about. assets.wp.envatoextensions.com

> [!ABSTRACT] **Grok** (2025-09-15 19:22:53)
> The warning you're encountering is directly related to Envato's recent discontinuation of their Extensions service, including the WordPress plugin and token generation system that powered one-click installations for Elementor Template Kits (and other assets). This change took effect on August 21, 2025, which is why the generate-token page now shows the "discontinued and no longer supported" message, and any attempt to use the old integration (like connecting via assets.wp.envatoextensions.com) triggers errors or warnings in tools like Elementor.
> 
> ### Why This Happened
> Envato decided to sunset their Extensions as part of a shift in focus toward AI-powered tools (like ImageGen, VideoGen, and MusicGen in Envato Labs). The extensions were experimental, and maintaining them required too much ongoing investment. This affects all their extensions for WordPress, Adobe apps, Canva, Figma, and more—but specifically for WordPress users, it breaks the seamless import process for Envato Elements subscribers.
> 
> If you're an Envato Elements subscriber, you can still access and download your Template Kits; you just need a new manual installation method. (Note: This applies to Elements subscriptions; if you purchased from ThemeForest or another Envato Market, the process is similar but doesn't require a subscription for downloads.)
> 
> ### How to Install Elementor Template Kits Now
> Envato recommends using the free "Template Kit Import" plugin as a replacement. This handles the ZIP file upload and import directly in WordPress, without needing tokens or the old extension. Here's a step-by-step guide:
> 
> 1. **Download the Template Kit**:
>    - Log in to your Envato account at [elements.envato.com](https://elements.envato.com) (or the relevant marketplace like ThemeForest).
>    - Search for and select your desired Elementor Template Kit.
>    - Click "Download" and choose the "Installable WordPress Kit" or "ZIP" option (it should be a .zip file containing the templates).
> 
> 2. **Install the Required Plugins in WordPress**:
>    - Go to your WordPress admin dashboard > Plugins > Add New.
>    - Search for and install "Template Kit Import" (free from Envato).
>    - Also ensure Elementor (free version) is installed and activated. If you're using Elementor Pro, that's fine too, but the free version works for basic kits.
>    - Optional but recommended: Install "Envato Market" plugin (also free) if you want to verify licenses or downloads directly in WordPress.
> 
> 3. **Import the Kit**:
>    - In your WordPress dashboard, go to Plugins > Add New (or if already installed, look under Installed Plugins).
>    - Find "Template Kit Import" and click "Start Import" or navigate to its dedicated page (it may appear under Appearance > Template Kit Import or a similar menu).
>    - Upload the downloaded .zip file.
>    - Follow the on-screen prompts to import the templates, styles, and assets. It will automatically handle Elementor compatibility.
> 
> 4. **Apply the Templates in Elementor**:
>    - Once imported, go to Pages > Add New (or edit an existing page).
>    - Edit with Elementor.
>    - In the Elementor editor, click the folder icon (Templates) in the widget panel.
>    - Select your imported kit templates and insert them as needed.
> 
> ### Common Issues and Troubleshooting
> - **PHP Zip Extension Error**: If you see "PHP Zip Extension not loaded," contact your hosting provider to enable the ZIP module in PHP (it's required for unpacking the kit files).
> - **Invalid ZIP File Warning**: Ensure you're downloading the correct "WordPress Kit" ZIP from Envato—not a demo or preview file. Re-download if needed, and avoid using theme installers (Appearance > Themes); that's not for kits.
> - **Missing Styles/Images After Import**: Enable Flexbox Container in Elementor settings (Elementor > Settings > Features). Also, clear your site's cache and regenerate CSS (Elementor > Tools > Regenerate Files).
> - **If You're Not an Elements Subscriber**: For one-time purchases (e.g., from ThemeForest), download the ZIP directly from your account and follow the same import steps—no plugin needed beyond Template Kit Import.
> - **Localhost Setups (e.g., XAMPP)**: Envato doesn't support debugging these; check your local software docs for ZIP/PHP issues.
> 
> This new method is more manual but reliable and doesn't rely on the discontinued service. If you run into specific errors during import, share the exact message for more targeted help. For official details, check Envato's support article on the sunset: [Sunsetting Extensions](https://help.elements.envato.com/hc/en-us/articles/49783425668761-Sunsetting-Extensions).

