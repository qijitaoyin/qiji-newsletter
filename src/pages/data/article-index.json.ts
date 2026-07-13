import type { APIRoute } from "astro";
import { publishedArticles, publishedIssueArchives } from "../../data/articles";

const compactArticle = (article: (typeof publishedArticles)[number]) => ({
  slug: article.slug,
  sourceId: article.sourceId,
  issueId: article.issueId,
  title: article.title,
  category: article.category,
  author: article.author,
  date: article.date,
  issue: article.issue,
  readTime: article.readTime,
  excerpt: article.excerpt,
  image: article.image,
  imageCaption: article.imageCaption,
  tags: article.tags,
  order: article.order
});

export const GET: APIRoute = () =>
  new Response(
    JSON.stringify({
      articles: publishedArticles.map(compactArticle),
      issues: publishedIssueArchives
    }),
    {
      headers: {
        "content-type": "application/json; charset=utf-8",
        "cache-control": "public, max-age=300"
      }
    }
  );
