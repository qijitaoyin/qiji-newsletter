import {
  articleTags,
  getArticlesByIssue,
  issueArchives,
  latestIssue,
  latestIssueArticles
} from "./articles";

export { articleTags, latestIssue };

export const featuredArticles = latestIssueArticles.map((article) => ({
  category: article.category,
  title: article.title,
  author: article.author,
  date: article.date,
  excerpt: article.excerpt,
  href: `/articles/${article.slug}/`,
  image: article.image
}));

export const currentIssueContent = {
  editorNote: featuredArticles[0],
  sections: Object.values(
    featuredArticles.slice(1).reduce(
      (groups, article) => {
        const title = article.category.startsWith("如是我聞") ? "如是我聞" : article.category;
        groups[title] = groups[title] ?? { title, articles: [] };
        groups[title].articles.push(article);
        return groups;
      },
      {} as Record<string, { title: string; articles: typeof featuredArticles }>
    )
  )
};

export const throwbackArticles = issueArchives.slice(1, 3).flatMap((issue) =>
  getArticlesByIssue(issue.id).slice(0, 1).map((article) => ({
    year: issue.date.slice(0, 4),
    issueNumber: issue.issueNumber,
    title: article.title,
    author: article.author,
    href: `/articles/${article.slug}/`,
    image: article.image
  }))
);

export const archiveIssues = issueArchives.map((issue) => ({
  label: issue.label,
  issue: `${issue.issueNumber}・${issue.articleCount} 篇`,
  href: issue.href
}));

export const categories = Array.from(
  new Set(latestIssueArticles.map((article) => article.category))
);

export const getTagByCategory = (category: string) =>
  articleTags.find((tag) => tag.label === category);
