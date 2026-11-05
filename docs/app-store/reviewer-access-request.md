# 审核访问沟通稿（尚未发送）

收件对象：Apple App Review，通过开发者支持的审核咨询入口。用途：在开发演示模式前确认 2.1(a) 的替代审核方式是否被接受。这不是已经批准或已经实现演示模式的声明。当前没有发送授权，不自动提交给 Apple。

## Subject

Request for guidance on demo-mode review access — Tidemeld (6830942092)

## Message

Hello App Review team,

I am preparing the first iOS release of Tidemeld, a free, open-source, independent Weibo client.

App Apple ID: 6830942092
Bundle ID: io.github.leonfox28.maxbo
Planned storefront: United States

The app signs users in through Weibo's official web page and uses the resulting session for direct access to Weibo. I do not control Weibo's authentication system. Sign-in with a dedicated test account still requires a one-time SMS code sent to the account's phone, so providing a username and password alone would not reliably give your reviewers independent access. I cannot disable that verification through my app.

The app now offers limited guest browsing: Home displays public posts as native cards with media viewing and pull-to-refresh, and reviewers can also view the native trending list and open public Weibo web search results. Weibo limits the guest feed to its first page. This guest path does not cover the following feed, notifications or account interactions.

Before implementing an alternative, I would like to ask whether you would approve a built-in, fully featured demo mode for review under Guideline 2.1(a) in these circumstances, or recommend another supported way to provide access.

The proposed mode would be openly available to every user, clearly labeled as sample data, and use the same app screens for the feed, post details, search, profiles, media, notifications, settings and interaction flows. Writes in this mode would affect only local sample data. Real Weibo sign-in and live functionality would remain available, and the review notes would explain exactly which actions are simulated. It would not disable or conceal live features during review.

Would this proposed approach meet your access requirements, and what further evidence or live-service testing access would you need? The demo mode is not yet implemented, and I am seeking your guidance before relying on it for submission.

Thank you.
