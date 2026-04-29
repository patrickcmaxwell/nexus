---
id: "unknown"
title: "Friendly greeting"
date: "2026-02-10T11:51:03.452000"
tags: ["conversation"]
---

# Friendly greeting

> [!INFO] **User** (2026-02-10 11:51:03)
> Media attached: audio
>  Hey, who we talking to?

> [!ABSTRACT] **Grok** (2026-02-10 11:51:03)
> Media attached: audio
> You can call me Eve.

> [!INFO] **User** (2026-02-10 11:51:09)
> Media attached: audio
>  How does you? I was checking.

> [!ABSTRACT] **Grok** (2026-02-10 11:51:09)
> Media attached: audio
> I'm doing well, thanks. Just here, listening.

> [!ABSTRACT] **Grok** (2026-02-10 11:51:17)
> Media attached: audio
> Always. What's on your mind today?

> [!INFO] **User** (2026-02-10 11:51:17)
> Media attached: audio
>  Yeah, as always.

> [!INFO] **User** (2026-02-10 11:52:02)
> Media attached: audio
>  So, I'm thinking about building something, and there's a slight competitor that I think is probably a few steps ahead, and I want to know everything you can tell me about. Then I might ask you a few questions, but it's called builder.io. Without me browsing around their stupid marketing site, can you just give me the full rundown of what that thing does?

> [!ABSTRACT] **Grok** (2026-02-10 11:52:47)
> Media attached: audio
> Builder.io is basically an **AI-powered visual development platform** that acts like a frontend engineer for your team. It lets you generate, edit, and ship web and mobile experiences super fast—often in seconds instead of weeks—while plugging right into your existing codebase, design system, and tech stack.
> 
> At its core, it's a mix of visual drag-and-drop editor and headless CMS, but heavily juiced up with AI in twenty twenty-six. You connect it to your site (React, Next.js, Vue, whatever), and then non-devs like marketers or designers can build or tweak pages, sections, or full features without bugging engineers constantly.
> 
> Key bits:
> 
> - **Visual Editor** — Drag and drop your own custom components, or their basics, to build layouts. It's responsive, supports A/B testing, personalization, scheduling. Content gets fetched via API and rendered like normal code.
> 
> - **AI Features** — Stuff like Fusion (their AI agent) that takes prompts, Figma designs, or Jira tickets and spits out production-ready code using your design tokens and components. Visual Copilot turns Figma files into clean code fast. You can iterate visually or with the agent, then review and ship through your usual process.
> 
> - **Publish** — Their enterprise-grade visual CMS side for managing content, pages, and optimizing without devs.
> 
> It integrates with Figma, Slack, Jira, Linear, Git repos—pretty much anywhere you work. Output is real code you own, no vendor lock-in. Security's solid, SOC two compliant, doesn't train on your data.
> 
> Here are some shots of the drag-and-drop editor in action—shows how you pull in custom React components and build pages visually.<grok:render card_id="b32803" card_type="image_card" type="render_searched_image">
> <argument name="image_id">3</argument>
> <argument name="size">"LARGE"</argument>
> </grok:render><grok:render card_id="50b167" card_type="image_card" type="render_searched_image">
> <argument name="image_id">4</argument>
> <argument name="size">"LARGE"</argument>
> </grok:render>
> 
> And here's what the AI design-to-code looks like—Figma straight to React/Tailwind code.<grok:render card_id="737bfd" card_type="image_card" type="render_searched_image">
> <argument name="image_id">0</argument>
> <argument name="size">"LARGE"</argument>
> </grok:render>
> 
> Pricing starts free for tinkering, then Pro at thirty quid per user a month, up to Enterprise custom. Teams use it to 2x speed, launch heaps of pages, save engineering time—big brands like Zapier, Everlane swear by it.
> 
> That's the no-fluff rundown. Fire away with questions.

> [!INFO] **User** (2026-02-10 11:54:23)
> Media attached: audio
>  Okay, so if builder.io does all those things, that means it can technically integrate into something that I'm building. What does it cost to use their service with multiple websites?

> [!ABSTRACT] **Grok** (2026-02-10 11:54:55)
> Media attached: audio
> Yeah, it integrates nicely into whatever you're building—React, Next.js, whatever framework.
> 
> On costs for multiple websites: they price per **space**, and a space is basically a container for related projects/codebases. You can put multiple related sites or apps in one space if they share components or content—no hard limit on domains or sites inside a single space.
> 
> But for completely separate websites (different teams, no shared stuff), they recommend separate spaces. And non-Enterprise plans only give you **one space per subscription**.
> 
> So for multiple unrelated sites:
> 
> - Free: one space, totally free, but limited users and AI credits.
> 
> - Pro: $30 per user a month (up to five users base, then more at $30 each), one space.
> 
> - Team: $50 per user a month (up to twenty base), one space.
> 
> If you need, say, three separate sites, you'd spin up three separate Pro or Team subscriptions—one per space—which adds up quick with users.
> 
> For real multi-site scale without duplicating costs, go Enterprise: custom pricing, custom number of spaces, users, AI credits—tailored to how many sites you're running. That's where agencies or bigger setups land, often connecting multiple repos too.
> 
> No domain fees or per-site charges beyond that; it's all about users, credits, and spaces. Hit them up for a quote if you're going multi.

> [!INFO] **User** (2026-02-10 11:56:13)
> Media attached: audio
>  What happens when it, when it comes down to hosting?

> [!ABSTRACT] **Grok** (2026-02-10 11:56:43)
> Media attached: audio
> Builder.io doesn't host your site at all—**you** handle the hosting, same as always. It's not like Wix or Squarespace where they serve the pages.
> 
> Here's how it shakes out:
> 
> Builder pushes content (pages, sections, whatever you build visually or with AI) to **your** app or site via APIs or generated code. Your frontend code fetches that content at runtime—think dynamic loading after the page loads, super fast from their edge network.
> 
> You deploy and host the actual app wherever you want: Vercel, Netlify, AWS, Google Cloud, your own servers—pick your poison. Builder just plugs in, no matter the host.
> 
> For previews: You spin up a branch or staging deploy (like on Vercel preview links), point Builder's preview URL there so the team can see edits live. Then push to production—same process.
> 
> Even their "Publish" mode (the CMS/visual editor side) is just a content layer—it doesn't host the final pages; it integrates into your codebase so non-devs can manage stuff without touching code.
> 
> You keep full control: no vendor lock-in on hosting, no extra fees for bandwidth or uptime. It's all on your stack, Builder's just the content engine.
> 
> If you're building multiple sites, same rule—each gets hosted on its own infra, Builder connects per space/repo.
> 
> Makes sense?

