import {
  BellSimple,
  BookOpen,
  Browser,
  CalendarBlank,
  ChatsCircle,
  Cloud,
  Database,
  DeviceMobile,
  EnvelopeSimple,
  GraduationCap,
  Images,
  Lifebuoy,
  LockKey,
  ShieldCheck,
  Star,
  Trash,
  UserCircle,
  WarningCircle
} from "@phosphor-icons/react";
import type { IconComponent } from "./types";

export const site = {
  domain: "myleafy.space",
  homeUrl: "https://myleafy.space/",
  supportUrl: "https://myleafy.space/support",
  privacyUrl: "https://myleafy.space/privacy",
  appStoreUrl: "https://apps.apple.com/cn/search?term=MyLeafy%20%E5%8C%97%E4%BA%AC%E6%9E%97%E4%B8%9A%E5%A4%A7%E5%AD%A6",
  privacyChoicesUrl: "https://myleafy.space/privacy#privacy-rights",
  supportEmail: "support@myleafy.space",
  operatorName: "MyLeafy Developer",
  operatorNote: "The public developer name is the one shown on the App Store product page.",
  updatedAt: "July 15, 2026"
};

export const navItems = [
  { label: "Home", href: "/" },
  { label: "Features", href: "/features" },
  { label: "Support", href: "/support" },
  { label: "Privacy", href: "/privacy" }
];

export const appStoreLinks = [
  { label: "Support URL", value: site.supportUrl },
  { label: "Privacy Policy URL", value: site.privacyUrl },
  { label: "Marketing URL", value: site.homeUrl },
  { label: "User Privacy Choices URL", value: site.privacyChoicesUrl }
];

export const capabilityStats = [
  { label: "Campus", value: "Beijing Forestry University" },
  { label: "Default tab", value: "Timetable" },
  { label: "Academic data", value: "Zhengfang system" },
  { label: "Community", value: "Supabase" },
  { label: "Support", value: "In-app feedback" }
];

export const productCards: Array<{
  icon: IconComponent;
  label: string;
  title: string;
  body: string;
  detail: string;
}> = [
  {
    icon: CalendarBlank,
    label: "Timetable",
    title: "Today comes first",
    body: "Current week, today's classes, class details, exams, and reminders stay centered around the timetable.",
    detail: "Default"
  },
  {
    icon: GraduationCap,
    label: "Academics",
    title: "Academic tools stay together",
    body: "Grades, exams, study plans, degree requirements, credits, and classroom lookup live in the Academics tab.",
    detail: "Direct"
  },
  {
    icon: ChatsCircle,
    label: "Community",
    title: "Community is separate from login",
    body: "Posts, images, comments, likes, bookmarks, notices, and notifications are stored in MyLeafy Community, separate from school sessions.",
    detail: "Campus"
  },
  {
    icon: UserCircle,
    label: "Profile",
    title: "Settings and safety in one place",
    body: "Shared timetables, themes, cache sync, links, data safety, support, and privacy controls live in Profile.",
    detail: "Device"
  },
  {
    icon: Star,
    label: "Ratings",
    title: "Lightweight ratings",
    body: "Course and teacher ratings use star summaries for quick context without turning feedback into a heavy workflow.",
    detail: "Simple"
  },
  {
    icon: BellSimple,
    label: "Feedback",
    title: "Reports include context",
    body: "In-app feedback can include device, system, app version, login state, and last sync time.",
    detail: "Faster"
  },
  {
    icon: LockKey,
    label: "Privacy",
    title: "Data sources are listed",
    body: "School academic data, local cache, community service, and website hosting are listed separately.",
    detail: "Clear"
  },
  {
    icon: Cloud,
    label: "Links",
    title: "Public links stay stable",
    body: "Support, privacy policy, marketing URL, and privacy choices links are available for App Store Connect.",
    detail: "Public"
  }
];

export const appScreenshots = [
  {
    label: "Timetable",
    title: "Timetable",
    body: "Current week, today's classes, class details, and reminders are the first layer.",
    image: "/media/app-timetable.webp",
    alt: "MyLeafy weekly timetable on iPhone 17 Pro"
  },
  {
    label: "Community",
    title: "Community",
    body: "Feed, categories, trending posts, notices, and notifications stay in a separate tab.",
    image: "/media/app-community.webp",
    alt: "MyLeafy campus community on iPhone 17 Pro"
  },
  {
    label: "Academics",
    title: "Academics",
    body: "Grades, exams, classrooms, calendar, academic plans, and ratings are grouped together.",
    image: "/media/app-academics.webp",
    alt: "MyLeafy academic tools on iPhone 17 Pro"
  },
  {
    label: "Leafy AI",
    title: "Leafy AI",
    body: "Campus questions can be answered with structured information and source context.",
    image: "/media/app-ai-policy.webp",
    alt: "MyLeafy AI policy answer on iPhone 17 Pro"
  }
];

export const featureShowcases = [
  {
    label: "Timetable",
    title: "Weekly timetable",
    body: "Open MyLeafy and see the week at a glance, with classes arranged around the real rhythm of the school day.",
    image: "/media/app-timetable.webp",
    alt: "Weekly timetable in MyLeafy on iPhone 17 Pro"
  },
  {
    label: "Academics",
    title: "Academic tools",
    body: "Grades, honors, study plans, training programs, and other academic records stay in one organized area.",
    image: "/media/app-academics.webp",
    alt: "Academic tools in MyLeafy on iPhone 17 Pro"
  },
  {
    label: "Community",
    title: "Campus community",
    body: "Browse campus posts, search discussions, follow notices, and join everyday conversations.",
    image: "/media/app-community.webp",
    alt: "MyLeafy campus community on iPhone 17 Pro"
  },
  {
    label: "Grades",
    title: "Grades overview",
    body: "Review GPA, weighted average, credits, risk courses, and term results in one place.",
    image: "/media/app-grades.webp",
    alt: "Grades overview in MyLeafy on iPhone 17 Pro"
  },
  {
    label: "Calendar",
    title: "Academic calendar",
    body: "Understand the current teaching week, term rhythm, and upcoming holidays without counting dates manually.",
    image: "/media/app-calendar.webp",
    alt: "Academic calendar in MyLeafy on iPhone 17 Pro"
  },
  {
    label: "Study space",
    title: "Study materials",
    body: "Import files from WeChat or QQ, organize study materials, and keep coursework close to campus tools.",
    image: "/media/app-study-space.webp",
    alt: "Study space in MyLeafy on iPhone 17 Pro"
  },
  {
    label: "Classrooms",
    title: "Classroom availability",
    body: "Check free classrooms by date, room, or period and keep useful rooms in a short favorites list.",
    image: "/media/app-classroom.webp",
    alt: "Classroom availability in MyLeafy on iPhone 17 Pro"
  },
  {
    label: "Campus",
    title: "Venue information",
    body: "Find opening rules and practical details for sports venues across the east and west campuses.",
    image: "/media/app-venues.webp",
    alt: "Campus venue information in MyLeafy on iPhone 17 Pro"
  },
  {
    label: "Campus policy",
    title: "Health policy",
    body: "Turn dense campus notices into readable, structured information while keeping the original source available.",
    image: "/media/app-health-policy.webp",
    alt: "Campus health policy in MyLeafy on iPhone 17 Pro"
  },
  {
    label: "Ratings",
    title: "Teacher ratings",
    body: "Browse lightweight teacher and course ratings with clear filtering and concise summaries.",
    image: "/media/app-ratings.webp",
    alt: "Teacher ratings in MyLeafy on iPhone 17 Pro"
  },
  {
    label: "Leafy AI",
    title: "Campus answers",
    body: "Ask a campus question and receive a structured answer with the relevant policy context.",
    image: "/media/app-ai-policy.webp",
    alt: "Leafy AI campus answer on iPhone 17 Pro"
  }
];

export const workflowCards: Array<{
  icon: IconComponent;
  title: string;
  body: string;
}> = [
  {
    icon: DeviceMobile,
    title: "Built for frequent checks",
    body: "Timetable first, community separate, academic tools grouped, profile for settings and safety."
  },
  {
    icon: Database,
    title: "Data boundaries are explicit",
    body: "School academic system, local SwiftData cache, MyLeafy Community, and Cloudflare static hosting are listed separately."
  },
  {
    icon: Lifebuoy,
    title: "Support and privacy stay public",
    body: "Support URL, privacy policy, marketing URL, and privacy choices URL are stable public links."
  }
];

export const featureBands: Array<{
  icon: IconComponent;
  label: string;
  title: string;
  body: string;
}> = [
  {
    icon: CalendarBlank,
    label: "Timetable",
    title: "Open to today's schedule",
    body: "The timetable is the default tab, with current week, daily summary, class details, and latest successful sync."
  },
  {
    icon: GraduationCap,
    label: "Academics",
    title: "Academic tools in one tab",
    body: "Grades, exams, academic plans, classrooms, calendar, and ratings are grouped in Academics."
  },
  {
    icon: UserCircle,
    label: "Profile",
    title: "Profile, sharing, and support",
    body: "Profile manages shared timetables, personal content, links, themes, cache sync, data safety, and support."
  },
  {
    icon: ChatsCircle,
    label: "Community",
    title: "Campus discussion",
    body: "Profiles, posts, images, comments, likes, notices, feedback, ratings, and shared timetable data are stored in MyLeafy Community."
  }
];

export const homeDataBoundaries = [
  {
    label: "School system",
    value: "Zhengfang",
    body: "Login, timetable, grades, exams, academic plans, degree requirements, and classroom lookup come from the school system."
  },
  {
    label: "Local cache",
    value: "SwiftData",
    body: "Recently synced classes, grades, notes, reminders, bookmarks, and countdowns are stored on the current device."
  },
  {
    label: "Community service",
    value: "Supabase",
    body: "Profiles, posts, comments, likes, notifications, notices, feedback, ratings, and shared timetable data are stored in MyLeafy Community."
  },
  {
    label: "Website hosting",
    value: "Cloudflare",
    body: "Product information, support, privacy policy, and App Store public links."
  }
];

export const resourceLinks = [
  {
    title: "Support",
    body: "Login, sync, parsing, community, ratings, and shared timetable issues.",
    href: site.supportUrl,
    cta: "Open support"
  },
  {
    title: "Privacy Policy",
    body: "How MyLeafy handles school login, local cache, community data, feedback, and sharing.",
    href: site.privacyUrl,
    cta: "Read policy"
  },
  {
    title: "Privacy Choices",
    body: "Access, correction, and deletion requests for community profile, feedback, or content data.",
    href: site.privacyChoicesUrl,
    cta: "View choices"
  }
];

export const footerGroups = [
  {
    title: "Product",
    links: [
      { label: "Features", href: "/features" },
      { label: "Data sources", href: "/features#data" },
      { label: "Shared timetable", href: "/share/timetable" }
    ]
  },
  {
    title: "Resources",
    links: [
      { label: "Support", href: "/support" },
      { label: "In-app feedback", href: "/support#in-app" },
      { label: "Data boundaries", href: "/features#data" },
      { label: "Email", href: `mailto:${site.supportEmail}` }
    ]
  },
  {
    title: "Legal",
    links: [
      { label: "Privacy Policy", href: "/privacy" },
      { label: "Privacy Choices", href: "/privacy#privacy-rights" },
      { label: "Third-party services", href: "/privacy#third-party" },
      { label: "Retention", href: "/privacy#retention" }
    ]
  },
  {
    title: "App Store",
    links: appStoreLinks.map((link) => ({ label: link.label, href: link.value }))
  }
];

export const supportChecklist = [
  "Device model, such as iPhone 15, iPad Air, or an Apple silicon Mac.",
  "iOS, iPadOS, or macOS version, plus the MyLeafy app version.",
  "The screen path where the issue appears, such as Academics -> Grades.",
  "Last sync time, plus the visible error message or screenshot text.",
  "Whether you are on campus network and whether you have re-signed into the school system."
];

export const supportTopics: Array<{
  icon: IconComponent;
  title: string;
  body: string;
}> = [
  {
    icon: Lifebuoy,
    title: "Technical support",
    body: "Send email or use in-app feedback. Include screen path, error message, device model, and app version when possible."
  },
  {
    icon: DeviceMobile,
    title: "In-app feedback",
    body: "Open Profile -> Support -> Feedback to include device model, system version, app version, login state, and last sync time."
  },
  {
    icon: WarningCircle,
    title: "Academic sync issues",
    body: "School network outages, expired sessions, and school page changes can cause sync failures. Re-sign in and retry sync first."
  },
  {
    icon: Trash,
    title: "Data requests",
    body: "For access, correction, or deletion requests for community profile, posts, or feedback, use in-app feedback or email."
  }
];

export const privacySummaryCards: Array<{
  icon: IconComponent;
  title: string;
  body: string;
}> = [
  {
    icon: LockKey,
    title: "School login is separate",
    body: "The school password is used to request login from the Zhengfang academic system. Community features use a separate MyLeafy session."
  },
  {
    icon: Database,
    title: "Local cache supports offline viewing",
    body: "Timetable, grades, notes, reminders, bookmarks, and sync state are stored on the current device. iPhone, iPad, and Mac caches are separate."
  },
  {
    icon: Cloud,
    title: "Community data is stored in MyLeafy Community",
    body: "Nickname, avatar, posts, comments, likes, notifications, feedback, ratings, and shared timetable data are stored in MyLeafy Community."
  },
  {
    icon: ShieldCheck,
    title: "Public policy and support links",
    body: "The support email and privacy policy are available at myleafy.space. New data processing will be reflected in the privacy policy."
  }
];

export const privacySections: Array<{
  id?: string;
  title: string;
  icon: IconComponent;
  items: string[];
}> = [
  {
    title: "Data We Process",
    icon: Database,
    items: [
      "School academic data: student ID, captcha, school session cookies, timetable, grades, exams, academic plans, degree requirements, available classrooms, and classroom occupancy come from the Zhengfang academic system.",
      "Login credentials: the school password is submitted to the Zhengfang academic system for login. This website does not collect the school password.",
      "Local cache: recently synced classes, grades, class notes, reminders, favorite classrooms, links, countdowns, theme preferences, sync time, and failure messages are stored on the current device. iPhone, iPad, and Mac keep separate local copies.",
      "Community profile: anonymous community session, bound school student ID, display name, nickname, avatar, major, grade, email verification state, and profile update time are used for community identity.",
      "Community content: posts, images, comments, likes, notice read state, teacher star ratings, and rating summaries are stored in MyLeafy Community.",
      "Shared timetable: sharing is created manually in the app. Published timetable data includes course name, teacher, location, week range, class period, semester, and publish time.",
      "Feedback: submitted feedback, optional contact information, device type, system version, app version, login state, and latest timetable sync time are used for support.",
      "Photos and files: MyLeafy reads selected photos only when you choose a community avatar, post image, or timetable background. On Mac, files are accessed through system open or save panels.",
      "Location and calendar: location is used only for weather and commute suggestions. Calendar permission is used only when you export timetable or reminders.",
      "Leafy AI: when you use free or subscription requests, your question and the local context you approve are sent through the Leafy AI service to DeepSeek. We process an Apple app transaction identifier, verified subscription transaction details, quota usage, reset times, and minimal request diagnostics to provide and protect the service. Your full question is not stored in quota records."
    ]
  },
  {
    title: "Purposes",
    icon: BookOpen,
    items: [
      "Request and display timetable, grades, exams, academic plans, and classroom information from the school system.",
      "Cache the latest successful sync on device for offline viewing.",
      "Provide community profile, posting, image upload, comments, likes, notifications, notices, feedback, and ratings.",
      "Let you share a read-only timetable with a seven-day, single-use invite code after you choose to publish it.",
      "Handle support requests for sync failures, login issues, parsing failures, and community service issues.",
      "Maintain community safety through deletion, posting limits, image limits, and admin audit logs."
    ]
  },
  {
    id: "third-party",
    title: "Third-party Services",
    icon: Cloud,
    items: [
      "Beijing Forestry University Zhengfang academic system is used for school login and academic data lookup.",
      "Supabase is used for MyLeafy Community, including anonymous auth, database, private image storage, Edge Functions, notifications, feedback, ratings, shared timetables, and admin tools.",
      "Cloudflare is used for myleafy.space DNS, static hosting, and support@myleafy.space email routing.",
      "Apple system capabilities are used for app distribution, photo and file selection, location, calendar, system sharing, notifications, and local storage.",
      "DeepSeek processes Leafy AI questions and approved context to generate responses. In self-provided API key mode, requests go directly from your device; the API key remains in the device Keychain."
    ]
  },
  {
    id: "retention",
    title: "Retention And Deletion",
    icon: Trash,
    items: [
      "Local device data stays on the current device. iPhone, iPad, and Mac caches are separate. You can clear timetable, grades, notes, reminders, bookmarks, and related cache in the app.",
      "Signing out clears the school session and community session. Local timetable and grade cache may remain for offline viewing until you clear it.",
      "Shared timetable access can be revoked by the sharer or removed by the viewer. Unused invite codes expire automatically.",
      "Community posts and comments may be soft-deleted or status-updated to keep notifications, audit logs, and safety records consistent.",
      "You can request access, correction, or deletion of community profile, feedback, or content data through in-app feedback or support@myleafy.space."
    ]
  },
  {
    id: "privacy-rights",
    title: "Privacy Choices And Rights",
    icon: ShieldCheck,
    items: [
      "Completing a community profile is your choice, but posting, commenting, and liking require a community nickname.",
      "Shared timetables are published by you. You can stop sharing or revoke a viewer at any time.",
      "Photo, file, location, and calendar permissions are controlled by you. Timetable, grades, academic tools, and community features can be used independently where permission is not needed.",
      "In a request, describe the data you want to access, correct, or delete. We may ask you to confirm identity through the signed-in app state or another reasonable method.",
      "Leafy AI subscriptions are processed by Apple. You can view or manage renewal in your Apple account, restore verified purchases in the app, or continue with the daily free allowance without subscribing."
    ]
  },
  {
    title: "Security And Limits",
    icon: WarningCircle,
    items: [
      "MyLeafy uses limited data for the stated features, but school page changes, campus network restrictions, and third-party service outages may affect availability.",
      "Do not send school passwords, captchas, or full identity documents in support requests.",
      "Community images are stored privately and read through signed links, but avoid uploading other people's private information."
    ]
  },
  {
    title: "Contact",
    icon: EnvelopeSimple,
    items: [
      `Support and privacy requests: ${site.supportEmail}.`,
      "You can also open Profile -> Support -> Feedback in the app.",
      `Operator: ${site.operatorName}. ${site.operatorNote}`,
      `Last updated: ${site.updatedAt}.`
    ]
  }
];

export const metadataNotes: Array<{
  icon: IconComponent;
  title: string;
  body: string;
}> = [
  {
    icon: Browser,
    title: "Cloudflare Pages",
    body: "Root directory: site. Build command: npm run build. Output directory: dist."
  },
  {
    icon: EnvelopeSimple,
    title: "Email Routing",
    body: "Forward support@myleafy.space through Cloudflare Email Routing, then submit the support URL to App Store Connect."
  },
  {
    icon: Images,
    title: "Public Contact",
    body: "Support email and privacy policy links are publicly accessible."
  },
  {
    icon: BellSimple,
    title: "In-app Feedback",
    body: "Use in-app feedback for issues that need device and sync context."
  },
  {
    icon: Star,
    title: "Ratings",
    body: "Ratings currently use one-to-five star summaries."
  }
];
