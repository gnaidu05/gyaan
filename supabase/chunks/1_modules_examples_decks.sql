-- ============================================================================
-- Gyaan LMS — Seed data, chunk 1 of 3 (run these AFTER the schema migrations,
-- in order 1 -> 2 -> 3). Split out because the combined file is large enough
-- that some browser-based SQL editors can silently truncate a single paste.
-- Each chunk deletes ONLY the tables it owns before inserting, so any single
-- chunk is safe to re-run on its own, any time, without running the others.
-- Caveat for THIS chunk: it owns modules, module_examples, and
-- flashcard_decks. flashcards (chunk 2) and quiz_questions (chunk 3) both
-- reference those with "on delete cascade", so re-running chunk 1 alone will
-- also clear flashcards and quiz_questions as a side effect — if that
-- happens, just run chunks 2 and 3 again afterward to repopulate them.
-- Re-running chunk 2 or chunk 3 alone never affects chunk 1's tables.
-- ============================================================================

begin;

-- Clean slate for the tables THIS chunk owns (FK-safe order).
delete from public.flashcard_decks;
delete from public.module_examples;
delete from public.modules;

-- ===========================================================================
-- MODULES
-- ===========================================================================
insert into public.modules (slug, title, subtitle, feature_area, order_index, core_content, icon, accent, points_reward)
values (
  'chat-basics',
  'Meet Claude: Chat Basics',
  'Conversations, context, and how to talk to Claude',
  'chat',
  1,
  E'Claude is an AI assistant you talk to in plain language — no special syntax, no menus. You type what you need, Claude responds, and you keep going. The whole interaction is a **conversation**, and that turn-by-turn structure is the single most important thing to understand.\n\n**Context is everything.** Claude reads your entire conversation each time it replies — every message you have sent and every message it has sent back. This shared history is called the *context window*. Because Claude remembers what was said earlier in the thread, you can say "make it shorter" or "use a more formal tone" without repeating yourself. Start a brand-new chat and that memory is gone — Claude begins fresh with no knowledge of your previous threads.\n\n**Iterate, do not restart.** The best results almost never come from the first message. Treat Claude like a capable colleague: give it a first draft request, then refine. "Good, but cut the jargon." "Add a line about pricing." "Now turn it into three bullet points." Each follow-up builds on everything before it.\n\n**Give Claude a role and a goal.** A quick line like "You are helping me, a busy professional, do X for audience Y" sharply improves the response. Claude adapts its tone, depth, and format to whatever you tell it about the situation.\n\n- **One chat = one topic.** Keep unrelated tasks in separate conversations so the context stays clean.\n- **Longer is not always better** — but relevant detail always helps. Paste the actual email, the real data, the exact error.\n- **Ask Claude to ask you questions** ("what do you need to know from me?") when you are not sure what to include.',
  '💬',
  'from-sky-500 to-indigo-400',
  100
);

insert into public.modules (slug, title, subtitle, feature_area, order_index, core_content, icon, accent, points_reward)
values (
  'prompting',
  'Prompting Fundamentals',
  'Be specific, give context, show examples',
  'prompting',
  2,
  E'A *prompt* is simply the instruction you give Claude. Vague prompts get generic answers — specific prompts get useful ones. Prompting is a skill, and a handful of habits will take you most of the way there.\n\n**1. Be specific about the outcome.** Instead of "write about our product," say "write a 120-word LinkedIn post announcing our product to operations managers, friendly but not salesy, ending with a question." State the length, audience, tone, and format you want. Claude cannot read your mind — but it is very good at following clear direction.\n\n**2. Give context.** Paste the source material: the data, the previous email, the transcript, the brand guidelines. Claude reasons from what you provide. The more relevant raw material it has, the less it has to guess.\n\n**3. Show an example.** If you have a sample of the style or format you want ("here is a headline I loved — write five more like it"), include it. Showing one good example is often worth a paragraph of description. This is called *few-shot* prompting.\n\n**4. Tell Claude who to be.** A role primer — "act as a skeptical CFO reviewing this" — shapes the whole response.\n\n**5. Ask for structure.** Request a table, numbered steps, or a specific template and Claude will format accordingly.\n\n- **Split big asks into steps.** "First outline it, then we will draft each section."\n- **Say what to avoid** as clearly as what you want ("no buzzwords, no exclamation marks").\n- **If the answer misses, do not just rephrase — add the missing constraint.** Nine times out of ten the fix is more context, not different wording.',
  '✍️',
  'from-fuchsia-500 to-pink-400',
  100
);

insert into public.modules (slug, title, subtitle, feature_area, order_index, core_content, icon, accent, points_reward)
values (
  'projects',
  'Projects & Persistent Context',
  'Reusable knowledge and custom instructions',
  'projects',
  3,
  E'A single chat forgets everything the moment you close it. **Projects** solve that. A Project is a dedicated workspace that bundles together custom instructions and reference files, so every conversation you start inside it already knows your context.\n\n**Custom instructions** are standing orders that apply to every chat in the Project — your tone of voice, your audience, your rules ("always use British spelling," "never promise delivery dates," "we are a B2B company selling to hospitals"). You set them once instead of repeating them in every message.\n\n**Project knowledge** is the set of documents you upload once and reuse forever: style guides, product specs, past reports, templates, policy PDFs. Claude can draw on all of it in any conversation in that Project. Ask a question and the answer is grounded in *your* material, not generic web knowledge.\n\n**Why it matters:** Projects turn Claude from a smart stranger into a colleague who already knows how your team works. Output becomes consistent across everyone using the Project, and onboarding a task takes seconds because the background is already loaded.\n\n- **One Project per recurring context** — a client, a product line, a function.\n- **Keep knowledge current.** Remove stale docs so Claude does not cite outdated information.\n- **Custom instructions beat repetition.** If you find yourself typing the same preamble every time, move it into the Project instructions.\n- Individual chats inside a Project still have their own separate context — the Project shares knowledge and instructions, not conversation history between chats.',
  '📁',
  'from-emerald-500 to-teal-400',
  100
);

insert into public.modules (slug, title, subtitle, feature_area, order_index, core_content, icon, accent, points_reward)
values (
  'artifacts',
  'Artifacts: Build Real Things',
  'Documents, apps, and visuals you can edit live',
  'artifacts',
  4,
  E'Sometimes you do not want an answer *in* the chat — you want a thing you can keep, edit, and share. That is an **Artifact**: a standalone piece of content that opens in its own panel beside the conversation. Documents, tables, code, charts, small web apps — all live as Artifacts.\n\n**Artifacts are editable and versioned.** Claude generates a first version — you say "make the header blue" or "add a fourth column" and Claude updates the same Artifact in place. You are not copying text back and forth — you are iterating on a living document.\n\n**Claude can build working software.** Ask for a calculator, an interactive dashboard, or a form and Claude writes real HTML/JavaScript that actually runs in the Artifact panel. You can click the buttons and see it work, then refine it by describing changes in plain language.\n\n**Great Artifact candidates:**\n- Polished documents (briefs, one-pagers, reports) you want to export.\n- Tables and comparison matrices you will keep tweaking.\n- Interactive tools — calculators, quizzes, mockups, dashboards.\n- Diagrams and charts that visualize your data.\n\n**How to get good Artifacts:** describe the purpose and audience, then iterate. "Build me a one-page pricing sheet" gets you a start — "make it two columns, add a FAQ, use our blue" gets you the finished piece. Because it is a real document, you can copy it out, download it, or share it when it is ready.',
  '🎨',
  'from-amber-500 to-orange-400',
  100
);

insert into public.modules (slug, title, subtitle, feature_area, order_index, core_content, icon, accent, points_reward)
values (
  'tool-use',
  'Tool Use & Connectors',
  'Let Claude search, browse, and use your tools',
  'tools',
  5,
  E'On its own, Claude reasons from its training and from what you paste in. **Tools and connectors** let it reach beyond that — to fetch live information and act in the systems you already use.\n\n**Web search** lets Claude look things up in real time. Ask about a recent announcement, current pricing, or this quarter''s news and Claude searches, reads the results, and answers with up-to-date information and links — instead of relying on what it learned during training.\n\n**Connectors** link Claude to your own tools: Google Drive, Gmail, GitHub, Slack, calendars, and many more. Once connected, Claude can pull a document from your Drive, read a thread, or reference a file without you copy-pasting it. Some connectors are read-only — others let Claude take actions, always within the permissions you grant.\n\n**The Model Context Protocol (MCP)** is the open standard that makes this extensible — teams can plug their own internal systems into Claude the same way.\n\n**Why it matters:** tools close the gap between "Claude gives good advice" and "Claude does the task using my real data and current facts."\n\n- **Ask Claude to search** when a fact might be recent or when you need a source you can verify.\n- **Verify what matters.** Tools reduce guesswork, but you still check anything high-stakes — click the links Claude cites.\n- **Grant only the access you need.** Connect the tools relevant to a task and review permissions.\n- **Be explicit:** "search the web for X," "check the file in my Drive called Y," so Claude uses the right tool for the job.',
  '🔌',
  'from-violet-500 to-purple-400',
  100
);

insert into public.modules (slug, title, subtitle, feature_area, order_index, core_content, icon, accent, points_reward)
values (
  'workflows',
  'Putting It Together: Real Workflows',
  'Chaining Claude into your daily work',
  'workflows',
  6,
  E'The real payoff comes when you stop using Claude for one-off questions and start building **workflows** — repeatable sequences where each step feeds the next. This module ties together everything before it: chat, prompting, Projects, Artifacts, and tools.\n\n**Chain the steps.** Most real work is a pipeline, not a single ask. Research → outline → draft → refine → format → repurpose. Do it as a conversation: each Claude output becomes the input to the next step, and you steer at every stage.\n\n**Anchor the workflow in a Project** so the context (your voice, your rules, your reference docs) is loaded automatically every time you run it. Reach for **tools** when a step needs live data, and produce **Artifacts** for the deliverables you will keep or share.\n\n**Make it repeatable.** Once a workflow works, save the sequence of prompts. Next time it is a template you fill in, not a blank page. Many people keep a note of their best prompt chains for recurring tasks.\n\n**Keep a human in the loop.** Claude drafts, accelerates, and organizes — you decide, verify, and own the result. The goal is not to remove your judgment but to remove the busywork around it.\n\n- **Start where it hurts most** — the recurring task you dread. Automate that first.\n- **Break it into stages** and get each stage right before chaining them.\n- **Reuse and refine.** Every good prompt chain you save compounds over time.',
  '🚀',
  'from-rose-500 to-red-400',
  100
);

-- ===========================================================================
-- MODULE EXAMPLES  (6 modules x 6 professions = 36 rows)
-- ===========================================================================

-- ---- chat-basics ----------------------------------------------------------
insert into public.module_examples (module_id, profession, scenario, sample_prompt, outcome) values
((select id from public.modules where slug='chat-basics'), 'recruitment',
 'You are sourcing senior backend engineers for a fintech client and need to send a first-touch message that does not read like every other recruiter''s. You want to draft one, then adjust the tone in the same thread until it feels human.',
 E'I''m a technical recruiter reaching out to a senior backend engineer at a competitor. Draft a short LinkedIn first message (under 90 words) for a fintech role — warm, specific, no buzzwords, and mention that the team owns payments infrastructure. Then wait, I''ll ask you to adjust the tone.',
 'Claude returns a tight outreach message, then refines it turn by turn as you ask for a warmer opener or a softer call to action — all without you re-explaining the role.'),
((select id from public.modules where slug='chat-basics'), 'marketing',
 'A product launch is three weeks out and you need a batch of tagline options for the campaign. You want to brainstorm out loud with Claude, react to what you like, and narrow down inside one conversation.',
 E'I''m a marketing manager launching a project-management app for small agencies. Give me 10 punchy tagline options — mix playful and confident. After I react, we''ll refine the ones I like.',
 'Claude produces a varied first batch, then hones in on your favorites as you give feedback, keeping every earlier idea in context so directions build on each other.'),
((select id from public.modules where slug='chat-basics'), 'sales',
 'You just finished a 45-minute discovery call and jotted messy notes. You need a clean recap and a follow-up email before the prospect goes cold, and you want to tweak the email''s tone before sending.',
 E'Here are my rough notes from a discovery call with a mid-market retail prospect: [paste notes]. Summarize the key pains and next steps, then draft a follow-up email that references two specific things they said. Keep it concise and consultative.',
 'Claude turns raw notes into a structured recap plus a personalized follow-up, and you refine the email''s tone in the same thread — cutting post-call admin from 20 minutes to two.'),
((select id from public.modules where slug='chat-basics'), 'engineering',
 'A deploy failed and you are staring at an unfamiliar stack trace at 6pm. You want to understand what it means and what to check first, asking follow-up questions as you narrow it down.',
 E'I got this error deploying a Node service: [paste stack trace]. Explain in plain terms what''s likely going wrong and the three most likely causes, ordered by probability. I''ll ask follow-ups as I check each one.',
 'Claude interprets the trace, ranks likely causes, and stays in context as you rule things out — acting like a pair-programmer who remembers everything you have tried so far.'),
((select id from public.modules where slug='chat-basics'), 'hr',
 'Leadership is changing the remote-work policy and you must announce it company-wide. The message needs to feel supportive, not corporate, and you want to test a few tones before it goes out.',
 E'I''m an HR partner announcing that we''re moving from fully remote to three days in-office. Draft a company-wide message that acknowledges this is a big change, explains the why honestly, and stays warm. Then I''ll ask you to make it less corporate.',
 'Claude drafts an empathetic announcement and adjusts warmth and directness on request, letting you find the right tone for a sensitive change without starting over.'),
((select id from public.modules where slug='chat-basics'), 'finance',
 'Your monthly management report shows marketing spend 18% over budget and the CFO wants an explanation by tomorrow. You want to reason through the variance with Claude and ask clarifying follow-ups.',
 E'Our monthly report shows marketing opex came in 18% over budget. Here''s the breakdown by line item: [paste figures]. Help me identify which lines drove the overage and draft three plausible explanations I can verify. I''ll ask follow-ups as I dig in.',
 'Claude pinpoints the lines driving the variance and proposes explanations to check, then refines the narrative as you feed it more detail — turning a spreadsheet into a story the CFO can read.');

-- ---- prompting ------------------------------------------------------------
insert into public.module_examples (module_id, profession, scenario, sample_prompt, outcome) values
((select id from public.modules where slug='prompting'), 'recruitment',
 'You need to write a job description that actually attracts the right people. Your last one was generic and drew unqualified applicants, so this time you give Claude the specifics and an example of a JD you admire.',
 E'Write a job description for a Senior Data Analyst. Context: remote-first SaaS company, 200 people, reports to Head of Analytics, must know SQL + dbt + Looker, salary band 95-120k. Tone: direct and human, no "rockstar" clichés. Match the style of this JD I like: [paste example]. Include a 5-bullet "what you''ll do" and a short "what we offer".',
 'By giving role specifics plus a style example, you get a JD in your target voice with the right structure — not a generic template you have to rewrite.'),
((select id from public.modules where slug='prompting'), 'marketing',
 'A batch of ad copy came back flat and off-brand. You decide to prompt properly this time: brand voice, audience, constraints, and an example of a headline that performed well.',
 E'Rewrite this ad copy for a Meta campaign. Audience: busy parents shopping for meal kits. Brand voice: warm, no hype, plain language, never use the word "delicious". Constraint: primary text under 125 characters. Here''s a headline that crushed last quarter as a style reference: "Dinner, minus the 5pm panic." Give me 6 variations.',
 'With audience, voice rules, a hard length limit, and a proven example, Claude returns on-brand variations that fit the ad platform — usable without a rewrite.'),
((select id from public.modules where slug='prompting'), 'sales',
 'Your cold emails get ignored. You want Claude to write one that is specific and personalized, so you supply the prospect''s context and paste a past email that actually booked meetings.',
 E'Write a cold email to a VP of Operations at a 500-person logistics firm. Trigger: they just announced expansion into a new region. Value prop: our software cuts route-planning time by 30%. Rules: under 90 words, one clear ask, no "hope this finds you well". Model it on this email that booked 4 meetings: [paste example].',
 'Claude produces a concise, trigger-based email in your proven style, giving you a personalized opener and a single clear ask instead of a generic template.'),
((select id from public.modules where slug='prompting'), 'engineering',
 'You need a utility function and want it right the first time. Instead of a vague ask, you specify the language, inputs, edge cases, and constraints precisely.',
 E'Write a TypeScript function `parseDuration(input: string): number` that converts strings like "1h30m", "45m", "2h" into total seconds. Requirements: handle hours and minutes only, return 0 for invalid input (don''t throw), no external libraries, include JSDoc and three example calls. Then list the edge cases you handled.',
 'A precise spec with inputs, edge cases, and constraints yields code that compiles and matches your requirements — plus a list of handled edge cases so you can review quickly.'),
((select id from public.modules where slug='prompting'), 'hr',
 'You are hiring for a role and need structured interview questions that map to real competencies, with a scoring rubric — not a random list off the internet.',
 E'Create a behavioral interview guide for a Customer Success Manager role. Competencies to assess: empathy, handling churn risk, cross-functional influence. For each, give 2 questions and a 1-3 scoring rubric describing what a weak, average, and strong answer sounds like. Keep questions open-ended and legally safe.',
 'By naming the competencies and asking for a rubric, you get a structured, defensible interview guide interviewers can score consistently — not just a question list.'),
((select id from public.modules where slug='prompting'), 'finance',
 'You need to explain how to build a specific model and want Claude''s output grounded in your actual numbers, with the formula logic spelled out step by step.',
 E'Explain how to build a 3-statement driver in Excel that links revenue growth to headcount. Assumptions: revenue $12M, 15% YoY growth, revenue-per-head target $250k. Show the exact formulas cell by cell, state each assumption explicitly, and flag where I''d normally sanity-check the output.',
 'With concrete assumptions and a request for cell-level formulas, Claude returns a precise, auditable walkthrough you can drop into a model instead of vague guidance.');

-- ---- projects -------------------------------------------------------------
insert into public.module_examples (module_id, profession, scenario, sample_prompt, outcome) values
((select id from public.modules where slug='projects'), 'recruitment',
 'You write dozens of outreach messages and offer letters a week, and they should all sound like your company. You set up a Project with your employer-brand materials so every draft is on-message automatically.',
 E'Custom instructions for this Project: "You help our talent team. Always match our employer brand: candid, human, no corporate jargon. Never over-promise on comp or timelines." I''ll upload our EVP one-pager, benefits summary, and three example messages. From now on, when I ask for outreach, ground it in these.',
 'Every chat in the Project starts already knowing your employer brand and benefits, so outreach and offer drafts are consistent across the whole recruiting team without re-briefing.'),
((select id from public.modules where slug='projects'), 'marketing',
 'Five people touch your brand''s content and it shows — voice drifts, terms vary. You create a brand Project holding your style guide and messaging framework so every asset comes out on-brand.',
 E'Set up this Project to enforce our brand. Custom instructions: "Follow the uploaded style guide exactly — voice, banned words, and formatting. We are B2B, sell to HR leaders." Knowledge: I''m adding the style guide, tone-of-voice doc, and our messaging pillars. When I ask for any asset, apply all of it.',
 'Anyone on the team can generate blog posts, emails, or social copy that follow the same voice and rules, because the brand system lives in the Project instead of in one person''s head.'),
((select id from public.modules where slug='projects'), 'sales',
 'Reps keep answering objections inconsistently and pricing questions get fumbled. You build a sales-enablement Project with your product one-pagers, pricing, and objection-handling playbook.',
 E'Create a Project for our sales team. Custom instructions: "You are a sales assistant. Only use the uploaded materials for product facts and pricing — never invent figures. Match our consultative tone." Knowledge: product one-pagers, current price list, competitor battlecards, objection-handling doc. Help reps draft responses grounded in these.',
 'Reps get accurate, on-message answers to product, pricing, and objection questions drawn from approved material, so the whole team sells with one voice and no made-up numbers.'),
((select id from public.modules where slug='projects'), 'engineering',
 'New engineers keep writing code that ignores your conventions, and reviews get bogged down in style nits. You set up a Project loaded with your codebase standards and architecture docs.',
 E'Project custom instructions: "You help engineers on our platform team. Follow our conventions exactly." Knowledge to add: our style guide, the architecture overview, our API design doc, and an example service that models our patterns. When I ask for code, match these conventions and cite which doc a decision came from.',
 'Code Claude drafts already follows your naming, structure, and API patterns, cutting review churn and helping new hires ramp on your standards without memorizing every doc.'),
((select id from public.modules where slug='projects'), 'hr',
 'Employees ask the same policy questions and answers vary by who responds. You create a Project containing the employee handbook and policy docs so answers are consistent and grounded.',
 E'Set up an HR knowledge Project. Custom instructions: "Answer employee questions using only the uploaded policies. If something isn''t covered, say so and suggest who to contact — never guess." Knowledge: employee handbook, leave policy, expense policy, code of conduct. Draft clear, friendly answers I can send.',
 'You get consistent, policy-accurate answers to routine questions grounded in the real handbook, with an honest "not covered" instead of a guess — saving time and reducing risk.'),
((select id from public.modules where slug='projects'), 'finance',
 'Month-end questions about how to treat a cost or which account to use get answered from memory and sometimes wrongly. You build a Project holding your accounting policies and chart of accounts.',
 E'Create a finance Project. Custom instructions: "Answer using only our uploaded accounting policies and chart of accounts. Cite the policy section. If treatment is ambiguous, flag it for review rather than deciding." Knowledge: accounting policy manual, chart of accounts, revenue-recognition guide, close checklist.',
 'The team gets policy-grounded answers on account coding and treatment with citations, and genuinely ambiguous cases get flagged rather than guessed — keeping the books consistent.');

-- ---- artifacts ------------------------------------------------------------
insert into public.module_examples (module_id, profession, scenario, sample_prompt, outcome) values
((select id from public.modules where slug='artifacts'), 'recruitment',
 'You are running a hiring loop with four interviewers and need a shared scorecard so feedback is structured and comparable across candidates, not a scatter of Slack messages.',
 E'Build an interview scorecard as a document. Role: Product Designer. Columns: competency, interviewer notes, score 1-4. Rows for: portfolio depth, collaboration, systems thinking, communication, culture-add. Add a final recommendation section with hire / no-hire and a confidence field. Make it clean and printable.',
 'Claude produces an editable scorecard Artifact you refine live (add a column, reweight a competency) and export for every interviewer, so candidate feedback is consistent and easy to compare.'),
((select id from public.modules where slug='artifacts'), 'marketing',
 'You are pitching a campaign concept and want something more tangible than a slide — an interactive landing-page mockup the team can click through in the review.',
 E'Build a single-page landing page mockup for a campaign launching our eco-friendly water bottle. Include a hero with headline and CTA, a 3-feature row, a testimonial block, and an email-signup form. Use a fresh green palette. Make it a working HTML mockup I can click.',
 'Claude generates a live, clickable landing-page Artifact you iterate on by describing changes ("make the hero taller, swap the CTA copy"), giving stakeholders something real to react to in the meeting.'),
((select id from public.modules where slug='artifacts'), 'sales',
 'A prospect keeps asking whether your product pays for itself. You want to hand them an interactive ROI calculator they can plug their own numbers into, instead of a static PDF.',
 E'Build an interactive ROI calculator as a web app. Inputs: number of employees, hours saved per employee per week, average hourly cost. Output: monthly savings, annual savings, and payback period given our $2,000/month price. Make the inputs sliders, show results updating live, and keep the design clean and on-brand-neutral.',
 'Claude builds a working calculator Artifact the prospect can manipulate live — you tweak the formula or styling in seconds and share a tool that makes your value concrete instead of asserted.'),
((select id from public.modules where slug='artifacts'), 'engineering',
 'You want to prototype a UI component to settle a design debate quickly, without spinning up a branch and a dev server just to show what you mean.',
 E'Build a working React-style component as an interactive Artifact: a multi-select filter dropdown with search, select-all, and a count badge showing how many options are chosen. Include sample data of 12 items. Make it self-contained and functional so I can click through the interactions.',
 'Claude produces a runnable component Artifact you can interact with immediately and refine by describing behavior changes, letting you validate a UI idea in minutes instead of scaffolding a project.'),
((select id from public.modules where slug='artifacts'), 'hr',
 'A new engineer starts Monday and onboarding is scattered across emails. You want a single, clean onboarding checklist you can reuse for every new hire and hand to their manager.',
 E'Build a new-hire onboarding checklist as a document. Group tasks into: Before Day 1, Week 1, First 30 Days, First 90 Days. Include owner (HR / Manager / IT) and a checkbox for each item. Cover accounts, equipment, intro meetings, benefits enrollment, and a 30-day check-in. Make it reusable.',
 'Claude generates a structured, editable checklist Artifact you refine once and reuse for every hire, giving managers a clear, consistent onboarding plan they can actually follow.'),
((select id from public.modules where slug='artifacts'), 'finance',
 'You need to walk leadership through next year''s budget scenarios and want an interactive view of how changing a couple of assumptions moves the bottom line, not three static tabs.',
 E'Build an interactive budget dashboard as a web app. Inputs: revenue growth %, headcount added, marketing spend. Show projected annual revenue, total costs, and net margin updating live as I change inputs, plus a simple bar chart comparing three preset scenarios (conservative, base, aggressive). Keep it clean.',
 'Claude builds a live budget dashboard Artifact where leadership sees assumptions flow to the bottom line in real time — you adjust drivers and chart formatting on the fly during the review.');

-- ---- tool-use -------------------------------------------------------------
insert into public.module_examples (module_id, profession, scenario, sample_prompt, outcome) values
((select id from public.modules where slug='tool-use'), 'recruitment',
 'Before an intake call with a hiring manager, you need current market context: what this role pays now and what a target candidate''s company has been up to lately — facts too recent to know from memory.',
 E'Search the web for current salary benchmarks for a Senior DevOps Engineer in Berlin, and check for any recent news about [Company] — funding, layoffs, or reorgs — that would affect how their engineers feel about moving. Summarize with sources I can click.',
 'Using web search, Claude returns up-to-date pay ranges and fresh company news with links you can verify, so you walk into the intake and outreach informed instead of guessing.'),
((select id from public.modules where slug='tool-use'), 'marketing',
 'You are planning a campaign and need to know what competitors are doing right now and which messaging angles are trending this quarter — information that changes constantly.',
 E'Search the web for how our top 3 competitors are currently positioning their meal-kit brands — pull their latest taglines and any campaigns from the last few months. Then summarize 3 messaging gaps we could own. Include links to what you found.',
 'Claude searches live sources, summarizes current competitor positioning with citations, and proposes gaps to exploit — grounding your campaign strategy in what is happening now, not last year.'),
((select id from public.modules where slug='tool-use'), 'sales',
 'You have a big call in an hour and want the latest on the account — recent news, leadership changes, earnings — plus the notes from your last meeting pulled straight from your files.',
 E'Search the web for recent news on [Prospect Company] from the last 60 days — earnings, leadership changes, product launches. Then check my Google Drive for the file "Acme - discovery notes" and combine both into a one-page pre-call brief with three tailored talking points.',
 'Claude pulls current news via search and your prior notes via the Drive connector, then merges them into a pre-call brief — so you open the call current on the account and continuous with your history.'),
((select id from public.modules where slug='tool-use'), 'engineering',
 'You are reviewing an unfamiliar part of your codebase and want Claude to read the actual repository files and the relevant docs rather than reasoning from a pasted snippet.',
 E'Using the GitHub connector, look at the `payments` module in our repo. Read `charge.ts` and its tests, then explain how refunds are handled and flag any edge cases the tests don''t cover. Also search the web for the current Stripe refund API docs to confirm the behavior.',
 'Claude reads the real files through the connector and checks current API docs via search, giving you an analysis grounded in your actual code and today''s external behavior rather than assumptions.'),
((select id from public.modules where slug='tool-use'), 'hr',
 'A manager asks whether a specific leave situation is handled correctly, and you need both your internal policy and the current legal position, which may have changed recently.',
 E'Check my Drive for our "Parental Leave Policy" doc and summarize what it says about phased return. Then search the web for any recent changes to statutory parental leave entitlements in the UK for 2026, and flag where our policy might now be below the legal minimum. Cite sources.',
 'Claude reads your internal policy via the connector and checks current statutory rules via search, surfacing any gap between the two with sources — so your guidance is both on-policy and legally current.'),
((select id from public.modules where slug='tool-use'), 'finance',
 'You are updating a forecast and need current reference data — interest rates, FX, or a competitor''s latest reported numbers — that must be accurate as of today, not from training.',
 E'Search the web for the current Bank of England base rate and today''s GBP/USD rate, and find [Competitor]''s most recent quarterly revenue and operating margin from their latest filing. Summarize the figures in a table with source links so I can drop them into my forecast assumptions.',
 'Claude retrieves the latest rates and reported figures with citations and lays them out in a table, so your forecast assumptions rest on verifiable current data instead of stale numbers.');

-- ---- workflows ------------------------------------------------------------
insert into public.module_examples (module_id, profession, scenario, sample_prompt, outcome) values
((select id from public.modules where slug='workflows'), 'recruitment',
 'A new requisition just opened and you want to run your whole front end of hiring — job description, screening rubric, outreach, and an interview kit — as one repeatable chain instead of four separate scrambles.',
 E'Let''s build my hiring kit for a Senior Product Manager req, step by step. Step 1: draft the JD from these notes: [paste]. Once I approve, Step 2: a screening rubric with must-haves and nice-to-haves. Step 3: three outreach message variants. Step 4: a structured interview guide. We''ll refine each step before moving on.',
 'Each approved output feeds the next, so you finish with a complete, consistent hiring kit from one conversation — and you can reuse the same prompt chain for the next req.'),
((select id from public.modules where slug='workflows'), 'marketing',
 'You publish one flagship piece a week and then have to slice it into social, email, and ad copy. You want a content workflow that goes from brief to a full multi-channel package.',
 E'Let''s run my content workflow. Step 1: from this brief [paste], write a 900-word blog post in our voice. Step 2: cut it into 3 LinkedIn posts. Step 3: a subject line + short email promoting it. Step 4: two ad variations. Keep everything consistent with the blog''s angle. We''ll approve each step before the next.',
 'One brief becomes a coordinated, on-voice package across every channel in a single chain, turning a full afternoon of repurposing into a guided session you steer step by step.'),
((select id from public.modules where slug='workflows'), 'sales',
 'You want a repeatable prospecting motion: research the account, personalize the outreach, build a follow-up sequence, and produce clean CRM notes — the same way every time.',
 E'Run my prospecting workflow for [Prospect]. Step 1: search recent news on the account and summarize a hook. Step 2: write a personalized first email using that hook. Step 3: a 3-touch follow-up sequence. Step 4: a tidy CRM note capturing the research and plan. Approve each step as we go.',
 'Research, outreach, follow-ups, and CRM notes come out of one connected flow, giving you a personalized, well-documented sequence per prospect that you can run identically across your whole list.'),
((select id from public.modules where slug='workflows'), 'engineering',
 'A ticket lands and you want to move from problem to pull request in a structured way — clarify, design, implement, test, and write the PR description — rather than diving straight into code.',
 E'Let''s work this ticket end to end: [paste ticket]. Step 1: restate the requirement and list open questions. Step 2: propose a short design with trade-offs. Step 3: implement it in Go following our conventions. Step 4: write table-driven tests. Step 5: draft the PR description. We''ll review each stage.',
 'The ticket flows through clarify, design, code, test, and PR write-up as one chain, producing reviewable work at each stage and a clean PR — with your judgment steering every step.'),
((select id from public.modules where slug='workflows'), 'hr',
 'Onboarding a new hire touches accounts, paperwork, intros, and check-ins across weeks. You want to run the whole thing as one orchestrated workflow so nothing slips.',
 E'Help me run onboarding for a new marketing hire starting in two weeks. Step 1: build the full onboarding checklist by phase and owner. Step 2: draft the welcome email and their first-week schedule. Step 3: write a 30-day check-in agenda. Step 4: a manager briefing on how to support them. We''ll refine each piece.',
 'The full onboarding — checklist, comms, schedule, and check-ins — comes out of one connected flow, so every new hire gets a consistent, thorough start and the manager knows exactly what to do.'),
((select id from public.modules where slug='workflows'), 'finance',
 'Month-end close is a recurring grind: pulling numbers, reconciling, analyzing variances, and writing the summary. You want to chain it into a guided workflow you run the same way every month.',
 E'Let''s run month-end close. Step 1: from this trial balance [paste], flag accounts that moved more than 10% vs last month. Step 2: for each, draft a variance explanation to verify. Step 3: build the management summary with key highlights. Step 4: a short list of follow-up questions for department heads. Approve each step.',
 'Reconciliation flags, variance narratives, and the management summary flow from one chain, turning a scattered multi-day close into a repeatable guided process you refine and reuse each month.');

-- ===========================================================================
-- FLASHCARD DECKS  (one per module)
-- ===========================================================================
insert into public.flashcard_decks (module_id, title, order_index) values
((select id from public.modules where slug='chat-basics'), 'Meet Claude: Chat Basics — Key Concepts', 1),
((select id from public.modules where slug='prompting'),   'Prompting Fundamentals — Key Concepts', 2),
((select id from public.modules where slug='projects'),    'Projects & Persistent Context — Key Concepts', 3),
((select id from public.modules where slug='artifacts'),   'Artifacts: Build Real Things — Key Concepts', 4),
((select id from public.modules where slug='tool-use'),    'Tool Use & Connectors — Key Concepts', 5),
((select id from public.modules where slug='workflows'),   'Putting It Together: Real Workflows — Key Concepts', 6);

commit;
