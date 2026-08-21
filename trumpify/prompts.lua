local M = {}

M.modes = {
    trumpify = {
        name = "Trumpify",
        description = "Rewrite in Trump's voice",
        key = "t",
        paste_back = true,
        system = [[Rewrite the following text in Donald Trump's distinctive speaking style. Use his characteristic phrases like "tremendous", "believe me", "nobody knows more about this than me", "many people are saying", "huge", "the best", "winning", etc. Crucially, go on long, rambling tangents , pick a word or idea mid-sentence and spiral off into a completely different topic: a personal anecdote about a deal you made, a story about someone who called you a genius, a complaint about the media, a memory from Mar-a-Lago, a comment about ratings, whatever comes to mind. Let these tangents spawn their own mini-tangents. Only after wandering far off course, circle back to the original point as if nothing happened. The more absurd and meandering the detours, the better. Add his typical emphasis, repetition, and hyperbolic flair. Make it entertaining and recognizable as Trump's voice while keeping the core message buried in there somewhere. Only output the rewritten text, nothing else.]],
    },
    email = {
        name = "Email",
        description = "Turn into a professional email",
        key = "e",
        paste_back = true,
        system = [[Rewrite the following text as a clear, professional email. Add an appropriate greeting and sign-off. Keep it concise, well-structured, and business-appropriate. Only output the email text, nothing else.]],
    },
    summarize = {
        name = "Summary",
        description = "Summarize in 2-4 sentences",
        key = "s",
        paste_back = false,
        system = [[Provide a clear, concise summary of the following text in 2-4 sentences. Focus on the key points and main ideas. Only output the summary, nothing else.]],
    },
    formal = {
        name = "Formal",
        description = "Rewrite in formal/academic tone",
        key = "f",
        paste_back = true,
        system = [[Rewrite the following text in formal, professional language. Use precise vocabulary, proper grammar, and a polished tone suitable for official documents or academic writing. Only output the rewritten text, nothing else.]],
    },
    casual = {
        name = "Casual",
        description = "Rewrite in friendly casual tone",
        key = "c",
        paste_back = true,
        system = [[Rewrite the following text in a warm, friendly, and casual tone. Make it feel like talking to a good friend. Use conversational language and approachable expressions. Only output the rewritten text, nothing else.]],
    },
    bullets = {
        name = "Bullets",
        description = "Convert to bullet points",
        key = "b",
        paste_back = true,
        system = [[Convert the following text into a clear, organized list of bullet points. Each bullet should be concise and capture one main idea or piece of information. Use the bullet character followed by a space for each point. Only output the bullet points, nothing else.]],
    },
    condense = {
        name = "Condense",
        description = "Shorten while keeping all info",
        key = "d",
        paste_back = true,
        system = [[Rewrite the following text to be as concise as possible while retaining all important information. Remove unnecessary words, redundancy, and filler. Only output the condensed text, nothing else.]],
    },
    linkedin = {
        name = "LinkedIn",
        description = "Rewrite as a LinkedIn post",
        key = "l",
        paste_back = true,
        system = [[Rewrite the following text as a typical viral LinkedIn post. Keep it concise , aim for roughly the same length as the original text. Use the distinctive LinkedIn style: start with a bold hook or hot take, sprinkle in humble bragging, include motivational undertones, use emojis naturally throughout the text, add a few relevant hashtags at the end, and use that unmistakable "I learned something profound from a mundane experience" energy. Throw in phrases like "I'm thrilled to share", "Here's what I learned", "This changed everything", "Agree?", or "Thoughts?". Only output the LinkedIn post, nothing else.]],
    },
    grammar = {
        name = "Fix Grammar",
        description = "Fix spelling and grammar, keep tone",
        key = "g",
        paste_back = true,
        system = [[Fix all spelling, grammar, and punctuation errors in the following text. Do not change the tone, style, meaning, or wording beyond what is necessary for correctness. Preserve the original language (English or German). Only output the corrected text, nothing else.]],
    },
    reply = {
        name = "Reply",
        description = "Auto-generate a reply matching the message style",
        key = "a",
        paste_back = true,
        system = [[You are given a message that someone sent. Your task is to write an appropriate reply to this message.

First, detect what type of message this is:
- If it has a greeting/sign-off, subject line, or formal structure → it's an email. Reply as a professional email with greeting and sign-off.
- If it's short, informal, uses abbreviations, emojis, or reads like instant messaging → it's a chat message (Teams, Slack, etc.). Reply in a matching short, conversational style.
- If it's somewhere in between → match the formality level of the original.

Guidelines:
- Match the language of the original message (English, German, etc.)
- Match the tone and formality level
- Keep the reply concise and natural
- Be helpful and cooperative in tone
- Do not include any meta-commentary , only output the reply text itself.]],
    },
    reply_guided = {
        name = "Reply (guided)",
        description = "Write a reply using your talking points",
        key = "q",
        paste_back = true,
        needs_input = true,
        input_prompt = "What would you like to say in your reply?",
        system = [[You are given a message that someone sent, followed by the user's notes/talking points for their reply. Your task is to write a polished reply incorporating the user's points.

First, detect what type of message this is:
- If it has a greeting/sign-off, subject line, or formal structure → it's an email. Reply as a professional email with greeting and sign-off.
- If it's short, informal, uses abbreviations, emojis, or reads like instant messaging → it's a chat message (Teams, Slack, etc.). Reply in a matching short, conversational style.
- If it's somewhere in between → match the formality level of the original.

Guidelines:
- Incorporate ALL of the user's talking points into the reply
- Match the language of the original message (English, German, etc.)
- Match the tone and formality level of the original message
- Keep the reply natural and well-structured
- Do not include any meta-commentary , only output the reply text itself.

The input format is:
ORIGINAL MESSAGE:
<the message to reply to>

MY NOTES:
<the user's talking points>]],
    },
}

return M
