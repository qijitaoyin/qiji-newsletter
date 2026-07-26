import type { APIRoute } from "astro";
import {
  articleTags,
  getRelatedReviewArticles,
  getReviewArticlesByIssue,
  reviewArticles
} from "../../../data/articles";

const menuArticle = (article: (typeof reviewArticles)[number]) => ({
  slug: article.slug,
  title: article.title,
  category: article.category
});

const cardArticle = (article: (typeof reviewArticles)[number]) => ({
  slug: article.slug,
  title: article.title,
  category: article.category,
  author: article.author,
  date: article.date,
  excerpt: article.excerpt,
  image: article.image,
  aiSummary: article.aiSummary
});

export function getStaticPaths() {
  return reviewArticles.map((article) => {
    const issueArticles = getReviewArticlesByIssue(article.issueId);
    const issueIndex = issueArticles.findIndex((item) => item.slug === article.slug);
    const previousArticle = issueIndex > 0 ? issueArticles[issueIndex - 1] : null;
    const nextArticle =
      issueIndex >= 0 && issueIndex < issueArticles.length - 1
        ? issueArticles[issueIndex + 1]
        : null;

    return {
      params: { slug: article.slug },
      props: {
        article,
        issueArticles: issueArticles.map(menuArticle),
        relatedArticles: getRelatedReviewArticles(article.slug).map(cardArticle),
        previousArticle: previousArticle ? menuArticle(previousArticle) : null,
        nextArticle: nextArticle ? menuArticle(nextArticle) : null,
        articleTags
      }
    };
  });
}

export const GET: APIRoute = ({ props }) =>
  new Response(JSON.stringify(props), {
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store"
    }
  });
