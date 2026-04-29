---
id: "unknown"
title: "BuddyBoss Achievement Posting Code"
date: "2025-08-27T13:41:39.126000"
tags: ["conversation"]
---

# BuddyBoss Achievement Posting Code

> [!INFO] **User** (2025-08-27 13:41:39)
> write me code for buddy boss that allows users to post achievements

> [!ABSTRACT] **Grok** (2025-08-27 13:42:08)
> To allow users to post achievements in BuddyBoss, we can leverage the GamiPress plugin, which integrates well with BuddyBoss to manage points, achievements, and ranks. Below is a solution that enables users to display and post about their achievements in the BuddyBoss activity feed. This involves creating a custom shortcode to display a user's achievements and a simple form for users to post about their earned achievements to the activity stream.
> 
> <xaiArtifact artifact_id="0b7252e5-519f-4e29-92de-be9e555e8043" artifact_version_id="44eb567b-7f2e-413c-b06a-1826dc907856" title="gamipress_achievements_shortcode.php" contentType="text/php">
> <?php
> // Add this code to your BuddyBoss child theme's functions.php or a custom plugin
> 
> // Register a shortcode to display user achievements and a form to post them
> add_shortcode('gamipress_user_achievements', 'custom_gamipress_user_achievements_shortcode');
> 
> function custom_gamipress_user_achievements_shortcode($atts) {
>     // Ensure GamiPress is active
>     if (!function_exists('gamipress_get_user_achievements')) {
>         return '<p>GamiPress plugin is required to display achievements.</p>';
>     }
> 
>     // Get the current user ID
>     $user_id = get_current_user_id();
>     if (!$user_id) {
>         return '<p>Please log in to view your achievements.</p>';
>     }
> 
>     // Get user achievements
>     $achievements = gamipress_get_user_achievements(array(
>         'user_id' => $user_id,
>         'achievement_types' => gamipress_get_achievement_types_slugs()
>     ));
> 
>     ob_start();
>     ?>
>     <div class="user-achievements">
>         <h3>Your Achievements</h3>
>         <?php if (!empty($achievements)) : ?>
>             <ul>
>                 <?php foreach ($achievements as $achievement) : 
>                     $achievement_post = get_post($achievement->ID);
>                     if ($achievement_post) :
>                 ?>
>                     <li>
>                         <?php echo esc_html($achievement_post->post_title); ?>
>                         <form method="post" action="">
>                             <input type="hidden" name="achievement_id" value="<?php echo esc_attr($achievement->ID); ?>">
>                             <input type="submit" name="post_achievement" value="Share to Activity Feed">
>                             <?php wp_nonce_field('post_achievement_nonce', 'post_achievement_nonce_field'); ?>
>                         </form>
>                     </li>
>                 <?php endif; endforeach; ?>
>             </ul>
>         <?php else : ?>
>             <p>No achievements earned yet.</p>
>         <?php endif; ?>
> 
>         <?php
>         // Handle form submission to post achievement to activity feed
>         if (isset($_POST['post_achievement']) && isset($_POST['achievement_id']) && isset($_POST['post_achievement_nonce_field']) && wp_verify_nonce($_POST['post_achievement_nonce_field'], 'post_achievement_nonce')) {
>             $achievement_id = intval($_POST['achievement_id']);
>             $achievement_post = get_post($achievement_id);
>             
>             if ($achievement_post && bp_is_active('activity')) {
>                 $content = 'I just earned the "' . esc_html($achievement_post->post_title) . '" achievement!';
>                 
>                 // Post to BuddyBoss activity feed
>                 bp_activity_add(array(
>                     'user_id'   => $user_id,
>                     'action'    => sprintf('%s shared an achievement', bp_core_get_user_displayname($user_id)),
>                     'content'   => $content,
>                     'component' => 'activity',
>                     'type'      => 'activity_update',
>                 ));
>                 
>                 echo '<p>Achievement shared to activity feed!</p>';
>             }
>         }
>         ?>
>     </div>
>     <?php
>     return ob_get_clean();
> }
> 
> // Add custom CSS for better styling
> add_action('wp_enqueue_scripts', 'custom_achievements_styles');
> function custom_achievements_styles() {
>     wp_enqueue_style('custom-achievements', get_stylesheet_directory_uri() . '/custom-achievements.css', array(), '1.0');
> }
> ?>
> </xaiArtifact>
> 
> <xaiArtifact artifact_id="23a07b9c-7a40-4058-96d0-cf9107d27ef1" artifact_version_id="d22d6e44-3e4a-4a7c-ae88-b078227af848" title="custom-achievements.css" contentType="text/css">
> .user-achievements {
>     margin: 20px 0;
>     padding: 20px;
>     background: #f9f9f9;
>     border-radius: 8px;
> }
> 
> .user-achievements h3 {
>     margin-bottom: 15px;
>     font-size: 24px;
> }
> 
> .user-achievements ul {
>     list-style: none;
>     padding: 0;
> }
> 
> .user-achievements li {
>     margin-bottom: 10px;
>     display: flex;
>     align-items: center;
>     justify-content: space-between;
> }
> 
> .user-achievements input[type="submit"] {
>     background: #0073aa;
>     color: #fff;
>     border: none;
>     padding: 8px 16px;
>     border-radius: 4px;
>     cursor: pointer;
> }
> 
> .user-achievements input[type="submit"]:hover {
>     background: #005177;
> }
> </xaiArtifact>
> 
> To use this code:
> 
> 1. **Prerequisites**:
>    - Ensure the **GamiPress** plugin is installed and activated on your WordPress site with BuddyBoss Platform.
>    - Ensure the **BuddyBoss Platform** is active with the activity component enabled.
> 
> 2. **Implementation**:
>    - Add the PHP code to your BuddyBoss child theme’s `functions.php` file or create a custom plugin.
>    - Place the CSS file (`custom-achievements.css`) in your child theme’s directory.
>    - Use the shortcode `[gamipress_user_achievements]` on any WordPress page or post to display the user’s achievements and a button to share them to the activity feed.
> 
> 3. **How It Works**:
>    - The shortcode displays a list of the logged-in user’s earned achievements (from GamiPress).
>    - Each achievement includes a “Share to Activity Feed” button.
>    - When clicked, the achievement is posted to the BuddyBoss activity feed with a message like “I just earned the [Achievement Name] achievement!”.
>    - The CSS provides basic styling for the achievements display.
> 
> 4. **Customization**:
>    - Modify the `custom-achievements.css` file to match your site’s design.
>    - Adjust the activity post content in the `bp_activity_add` function to change the message format.
>    - You can extend the shortcode to include achievement images or additional details by modifying the GamiPress API calls.
> 
> This solution assumes you’re using GamiPress for achievements, as it’s a popular and well-supported plugin for BuddyBoss. If you’re using another plugin like BadgeOS, let me know, and I can adjust the code accordingly. For further details on GamiPress integration with BuddyBoss, you can refer to the official BuddyBoss documentation.[](https://www.buddyboss.com/resources/docs/integrations/gamipress-buddyboss-integration/integration-setup/)

