# OpenAI allowlist — OpenAI API and CDN.
{
  hosts = [
    "api.openai.com"   # REST API (chat, embeddings, files, …)
    "openai.com"       # website / docs fetched by some SDK tooling
    "cdn.openai.com"   # static assets used by the Assistants API file viewer
  ];

  cidrs = [];
}
