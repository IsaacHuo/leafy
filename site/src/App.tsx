import { lazy, Suspense, useEffect, useState } from "react";
import type { ReactNode } from "react";
import {
  AppleLogo,
  ArrowRight,
  Buildings,
  CalendarBlank,
  ChatsCircle,
  CheckCircle,
  CloudCheck,
  Database,
  DeviceMobile,
  EnvelopeSimple,
  GraduationCap,
  House,
  Lifebuoy,
  LockKey,
  ShieldCheck,
  Sparkle
} from "@phosphor-icons/react";
import {
  appStoreLinks,
  appScreenshots,
  capabilityStats,
  featureShowcases,
  featureBands,
  footerGroups,
  homeDataBoundaries,
  navItems,
  privacySections,
  privacySummaryCards,
  resourceLinks,
  site,
  supportChecklist,
  supportTopics,
  workflowCards
} from "./content";
import type { IconComponent } from "./types";
import { CopyEmailButton } from "./components/CopyEmailButton";
import { ScrollReveal, StaggerReveal, TapButton } from "./components/MotionBits";

const AdminConsole = lazy(() => import("./admin/AdminConsole"));

const pageTitles: Record<string, string> = {
  "/": "MyLeafy | Campus Timetable and Student Tools",
  "/features": "MyLeafy Features",
  "/support": "MyLeafy Support",
  "/privacy": "MyLeafy Privacy Policy",
  "/admin": "MyLeafy Admin",
  "/share/timetable": "MyLeafy Shared Timetable",
  "/share/community/post": "MyLeafy Community Post"
};

const primaryButtonClass = "border border-primary bg-primary text-white shadow-primary hover:bg-primary-strong";
const secondaryButtonClass = "border border-black/10 bg-white text-text shadow-soft hover:border-black/20 hover:bg-primary-soft";
const panelClass = "rounded-[24px] border border-black/[0.08] bg-white p-6 shadow-[0_18px_50px_rgba(16,32,24,0.055)]";
const featuredPanelClass = "rounded-[24px] border border-primary/15 bg-primary-wash p-6 shadow-[0_18px_50px_rgba(31,106,69,0.07)]";
const ruleStackClass = "overflow-hidden rounded-[24px] border border-black/[0.08] bg-white shadow-[0_18px_50px_rgba(16,32,24,0.05)]";

function normalizedPath(pathname: string) {
  if (pathname === "/") {
    return "/";
  }

  return pathname.replace(/\/+$/, "");
}

function routeFromHref(href: string) {
  if (href.startsWith("mailto:")) {
    return href;
  }

  try {
    const url = new URL(href, window.location.origin);
    return `${normalizedPath(url.pathname)}${url.hash}`;
  } catch {
    return href;
  }
}

function usePathname() {
  const [path, setPath] = useState(() => normalizedPath(window.location.pathname));

  useEffect(() => {
    function syncPath() {
      setPath(normalizedPath(window.location.pathname));
    }

    window.addEventListener("popstate", syncPath);
    return () => window.removeEventListener("popstate", syncPath);
  }, []);

  return [path, setPath] as const;
}

export default function App() {
  const [path, setPath] = usePathname();
  const isAdminPath = path === "/admin" || path.startsWith("/admin/");
  const isShareTimetablePath = path === "/share/timetable" || path.startsWith("/share/timetable/");
  const isShareCommunityPostPath = path === "/share/community/post" || path.startsWith("/share/community/post/");
  const activePath = isAdminPath
    ? "/admin"
    : isShareTimetablePath
      ? "/share/timetable"
      : isShareCommunityPostPath
        ? "/share/community/post"
        : path === "/features" || path === "/support" || path === "/privacy"
          ? path
          : "/";
  const timetableInviteCode = isShareTimetablePath ? path.split("/").pop() ?? "" : "";
  const communityPostID = isShareCommunityPostPath ? path.split("/").pop() ?? "" : "";

  useEffect(() => {
    document.title = pageTitles[activePath];
  }, [activePath]);

  function navigate(href: string) {
    if (href.startsWith("mailto:")) {
      window.location.href = href;
      return;
    }

    if (href.startsWith("http")) {
      try {
        const url = new URL(href);
        const isLocalRoute = url.hostname === window.location.hostname || url.hostname === site.domain;

        if (!isLocalRoute) {
          window.location.href = href;
          return;
        }
      } catch {
        window.location.href = href;
        return;
      }
    }

    const next = routeFromHref(href);
    const [nextPath, hash = ""] = next.split("#");
    const targetPath = normalizedPath(nextPath || "/");
    window.history.pushState({}, "", `${targetPath}${hash ? `#${hash}` : ""}`);
    setPath(targetPath);

    window.setTimeout(() => {
      if (hash) {
        document.getElementById(hash)?.scrollIntoView({ behavior: "smooth", block: "start" });
      } else {
        window.scrollTo({ top: 0, behavior: "smooth" });
      }
    }, 0);
  }

  if (activePath === "/admin") {
    return (
      <Suspense fallback={<main className="grid min-h-[100dvh] place-items-center bg-paper p-6 text-text">Loading admin...</main>}>
        <AdminConsole />
      </Suspense>
    );
  }

  return (
    <div className="min-h-[100dvh] bg-paper text-text">
      <Header activePath={activePath} navigate={navigate} />
      <main>
        {activePath === "/" && <HomePage navigate={navigate} />}
        {activePath === "/features" && <FeaturesPage navigate={navigate} />}
        {activePath === "/support" && <SupportPage />}
        {activePath === "/privacy" && <PrivacyPage />}
        {activePath === "/share/timetable" && <ShareTimetablePage code={timetableInviteCode} />}
        {activePath === "/share/community/post" && <ShareCommunityPostPage postID={communityPostID} />}
      </main>
      <Footer navigate={navigate} />
    </div>
  );
}

function Header({ activePath, navigate }: { activePath: string; navigate: (href: string) => void }) {
  const isHome = activePath === "/";

  return (
    <header className={`${isHome ? "absolute" : "sticky border-b border-black/[0.06] bg-white/85 backdrop-blur-2xl"} top-0 z-40 w-full`}>
      <div className={`${isHome ? "mt-3 rounded-[22px] border border-white/70 bg-white/72 shadow-[0_12px_40px_rgba(16,32,24,0.08)] backdrop-blur-2xl md:mt-5" : ""} mx-auto flex max-w-7xl flex-wrap items-center gap-3 px-4 py-3 md:px-5`}>
        <a
          href="/"
          onClick={(event) => {
            event.preventDefault();
            navigate("/");
          }}
          className="leafy-pressable flex min-w-fit items-center gap-3 rounded-xl"
          aria-label="MyLeafy home"
        >
          <img className="h-9 w-9 rounded-[10px] border border-black/[0.06] shadow-soft" src="/app-icon.png" alt="MyLeafy app icon" />
          <strong className="text-xl font-semibold leading-none tracking-[-0.02em] text-text">MyLeafy</strong>
        </a>

        <nav className="leafy-scrollbar-none order-3 flex w-full min-w-0 gap-1 overflow-x-auto md:order-none md:ml-8 md:w-auto md:flex-1 md:items-center md:justify-center">
          {navItems.map((item) => {
            const route = routeFromHref(item.href).split("#")[0];
            const isActive = route === "/" ? activePath === "/" : activePath === route;

            return (
              <a
                key={item.href}
                href={item.href}
                onClick={(event) => {
                  event.preventDefault();
                  navigate(item.href);
                }}
                className={`leafy-pressable whitespace-nowrap rounded-xl px-3 py-2 text-sm font-medium transition-colors ${
                  isActive
                    ? "bg-primary-wash text-primary-ink"
                    : "text-text/60 hover:bg-primary-soft hover:text-text"
                }`}
              >
                {item.label}
              </a>
            );
          })}
        </nav>

        <div className="ml-auto flex items-center gap-2">
          <a
            href={`mailto:${site.supportEmail}`}
            className="leafy-pressable hidden rounded-xl px-3 py-2 text-sm font-medium text-text/60 transition-colors hover:bg-primary-soft hover:text-text sm:inline-flex"
          >
            Contact
          </a>
          <a
            href={site.appStoreUrl}
            className="leafy-pressable inline-flex min-h-10 items-center justify-center gap-2 rounded-xl bg-primary px-4 text-sm font-semibold text-white shadow-[0_10px_28px_rgba(31,106,69,0.22)] transition-colors hover:bg-primary-strong"
          >
            <AppleLogo size={16} weight="fill" aria-hidden />
            <span className="hidden sm:inline">App Store</span>
            <span className="sm:hidden">Get</span>
          </a>
        </div>
      </div>
    </header>
  );
}

function HomePage({ navigate }: { navigate: (href: string) => void }) {
  return (
    <>
      <section className="relative isolate min-h-[880px] overflow-hidden bg-white pt-28 md:min-h-[min(960px,100svh)] md:pt-36">
        <div className="absolute -right-40 top-8 -z-10 h-[620px] w-[620px] rounded-[44%_56%_64%_36%/52%_40%_60%_48%] bg-primary-wash opacity-90" aria-hidden />
        <div className="absolute bottom-10 left-[42%] -z-10 h-72 w-72 rounded-[64%_36%_42%_58%/42%_58%_42%_58%] bg-[#f3f8e9]" aria-hidden />

        <div className="mx-auto grid w-full max-w-7xl items-center gap-16 px-4 pb-20 md:px-6 lg:grid-cols-[0.9fr_1.1fr] lg:gap-8 lg:pb-24">
          <StaggerReveal className="relative z-10 max-w-2xl">
            <h1 className="text-[clamp(3.7rem,7vw,6.8rem)] font-semibold leading-[0.92] tracking-[-0.065em] text-text">
              Campus life,<br />in one place.
            </h1>
            <p className="mt-7 max-w-[620px] text-lg leading-relaxed text-text/64 md:text-xl">
              Timetable, academics, community, and the everyday tools built for BJFU students.
            </p>
            <div className="mt-9 flex flex-col gap-3 sm:flex-row">
              <AppStoreButton />
              <TapButton onClick={() => navigate("/features")} className={`${secondaryButtonClass} px-5 text-[15px] font-semibold`}>
                Explore features
                <ArrowRight size={17} weight="bold" aria-hidden />
              </TapButton>
            </div>
          </StaggerReveal>

          <HeroPhones />
        </div>
      </section>

      <ProofRail />

      <section className="overflow-hidden bg-white px-4 py-24 md:px-6 md:py-36">
        <ScrollReveal className="mx-auto grid max-w-7xl items-center gap-14 lg:grid-cols-[0.9fr_1.1fr] lg:gap-24">
          <div className="relative mx-auto w-full max-w-[500px]">
            <div className="absolute inset-[12%_-8%_5%_-8%] -z-10 rounded-[50%_50%_42%_58%/52%_44%_56%_48%] bg-primary-wash" aria-hidden />
            <PhoneFrame image={appScreenshots[0].image} alt={appScreenshots[0].alt} className="mx-auto w-[min(68vw,330px)]" />
          </div>
          <div className="max-w-xl">
            <span className="mb-7 grid h-12 w-12 place-items-center rounded-2xl bg-primary-wash text-primary-ink">
              <CalendarBlank size={24} weight="bold" aria-hidden />
            </span>
            <h2 className="text-4xl font-semibold leading-[1.04] tracking-[-0.045em] text-text md:text-6xl">Your timetable, beautifully simple.</h2>
            <p className="mt-6 text-lg leading-relaxed text-text/64">
              Open MyLeafy and see the week at a glance. Classes, rooms, reminders, and exam information stay close to the schedule you check every day.
            </p>
            <FeatureList items={["A clear week built around the school day", "Course details and reminders in context", "Calendar export when you need it elsewhere"]} />
          </div>
        </ScrollReveal>
      </section>

      <section className="border-y border-black/[0.05] bg-primary-soft px-4 py-24 md:px-6 md:py-36">
        <ScrollReveal className="mx-auto grid max-w-7xl items-center gap-16 lg:grid-cols-[0.92fr_1.08fr] lg:gap-24">
          <div className="max-w-xl lg:order-1">
            <span className="mb-7 grid h-12 w-12 place-items-center rounded-2xl bg-white text-primary-ink shadow-soft">
              <ChatsCircle size={24} weight="bold" aria-hidden />
            </span>
            <h2 className="text-4xl font-semibold leading-[1.04] tracking-[-0.045em] text-text md:text-6xl">More than a timetable.</h2>
            <p className="mt-6 text-lg leading-relaxed text-text/64">
              Academic tools and campus conversations have their own clear spaces, so checking grades never feels mixed up with browsing community posts.
            </p>
            <div className="mt-10 grid gap-0 border-y border-black/[0.08]">
              <StoryRow icon={GraduationCap} title="Academics" body="Grades, exams, credits, study plans, and classroom lookup." />
              <StoryRow icon={ChatsCircle} title="Community" body="Posts, notices, discussions, bookmarks, and notifications." />
              <StoryRow icon={Sparkle} title="Personal" body="Themes, reminders, notes, sharing, and everyday preferences." />
            </div>
          </div>
          <div className="relative min-h-[590px] lg:order-2">
            <div className="absolute left-[5%] top-0 z-10 w-[min(56vw,285px)] -rotate-[5deg]">
              <PhoneFrame image={appScreenshots[1].image} alt={appScreenshots[1].alt} />
            </div>
            <div className="absolute bottom-0 right-[3%] w-[min(56vw,285px)] rotate-[4deg]">
              <PhoneFrame image={appScreenshots[2].image} alt={appScreenshots[2].alt} />
            </div>
          </div>
        </ScrollReveal>
      </section>

      <HomeDataTrust />

      <section className="bg-primary px-4 py-16 text-white md:px-6 md:py-20">
        <ScrollReveal className="mx-auto flex max-w-7xl flex-col items-start justify-between gap-8 md:flex-row md:items-center">
          <div className="flex items-center gap-5">
            <img className="h-20 w-20 rounded-[22px] border border-white/15 shadow-[0_20px_50px_rgba(0,0,0,0.2)]" src="/app-icon.png" alt="MyLeafy app icon" />
            <div>
              <h2 className="text-3xl font-semibold tracking-[-0.035em] md:text-4xl">All set. Let’s get started.</h2>
              <p className="mt-2 text-base text-white/70">Make the everyday parts of campus life simpler.</p>
            </div>
          </div>
          <AppStoreButton light />
        </ScrollReveal>
      </section>
    </>
  );
}

function AppStoreButton({ light = false }: { light?: boolean }) {
  return (
    <TapButton
      href={site.appStoreUrl}
      className={`${light ? "border-white/15 bg-white text-primary-ink shadow-[0_16px_40px_rgba(0,0,0,0.18)] hover:bg-white/92" : primaryButtonClass} px-5 text-[15px] font-semibold`}
    >
      <AppleLogo size={20} weight="fill" aria-hidden />
      View on the App Store
    </TapButton>
  );
}

function PhoneFrame({ image, alt, className = "" }: { image: string; alt: string; className?: string }) {
  return (
    <div className={`phone-frame relative overflow-hidden rounded-[46px] border-[7px] border-[#111714] bg-[#111714] shadow-[0_35px_80px_rgba(15,42,26,0.2)] ${className}`}>
      <img className="h-auto w-full rounded-[38px] bg-white" src={image} alt={alt} loading="eager" decoding="async" />
    </div>
  );
}

function HeroPhones() {
  return (
    <div className="relative mx-auto min-h-[590px] w-full max-w-[650px] lg:min-h-[670px]" aria-label="MyLeafy app previews">
      <div className="hero-phone hero-phone-left absolute left-[3%] top-[10%] z-10 w-[min(53vw,310px)] -rotate-[5deg]">
        <PhoneFrame image={appScreenshots[0].image} alt={appScreenshots[0].alt} />
      </div>
      <div className="hero-phone hero-phone-right absolute bottom-[1%] right-[2%] w-[min(53vw,310px)] rotate-[4deg]">
        <PhoneFrame image={appScreenshots[1].image} alt={appScreenshots[1].alt} />
      </div>
    </div>
  );
}

function ProofRail() {
  const items = [
    { icon: Buildings, title: "BJFU", body: "Made for Beijing Forestry University." },
    { icon: CalendarBlank, title: "Timetable first", body: "The week you need, at a glance." },
    { icon: ShieldCheck, title: "Privacy by design", body: "Clear boundaries and local control." },
    { icon: DeviceMobile, title: "Built for iPhone", body: "Native, focused, and familiar." }
  ];

  return (
    <section className="border-y border-black/[0.05] bg-primary-soft px-4 md:px-6">
      <div className="mx-auto grid max-w-7xl divide-y divide-black/[0.07] md:grid-cols-4 md:divide-x md:divide-y-0">
        {items.map((item) => {
          const Icon = item.icon;
          return (
            <div key={item.title} className="px-1 py-7 md:px-7 md:py-9 first:md:pl-0 last:md:pr-0">
              <Icon size={25} weight="bold" className="text-primary-ink" aria-hidden />
              <p className="mt-5 text-base font-semibold tracking-[-0.015em] text-text">{item.title}</p>
              <p className="mt-2 text-sm leading-relaxed text-text/58">{item.body}</p>
            </div>
          );
        })}
      </div>
    </section>
  );
}

function FeatureList({ items }: { items: string[] }) {
  return (
    <div className="mt-8 grid gap-4">
      {items.map((item) => (
        <div key={item} className="flex items-start gap-3 text-[15px] leading-relaxed text-text/72">
          <CheckCircle className="mt-0.5 shrink-0 text-primary" size={19} weight="fill" aria-hidden />
          <span>{item}</span>
        </div>
      ))}
    </div>
  );
}

function StoryRow({ icon: Icon, title, body }: { icon: IconComponent; title: string; body: string }) {
  return (
    <div className="grid grid-cols-[44px_1fr] gap-4 border-b border-black/[0.08] py-5 last:border-b-0">
      <span className="grid h-10 w-10 place-items-center rounded-xl bg-white text-primary-ink shadow-soft">
        <Icon size={20} weight="bold" aria-hidden />
      </span>
      <div>
        <h3 className="text-base font-semibold text-text">{title}</h3>
        <p className="mt-1 text-sm leading-relaxed text-text/58">{body}</p>
      </div>
    </div>
  );
}

function HomeDataTrust() {
  const items = [
    { icon: Buildings, title: "School data", body: "Timetable and academics come from the official school system." },
    { icon: Database, title: "Local cache", body: "Recent information stays on your device for reliable everyday access." },
    { icon: CloudCheck, title: "Community service", body: "Community content is separate from your school login session." }
  ];

  return (
    <section className="bg-white px-4 py-24 md:px-6 md:py-32">
      <ScrollReveal className="mx-auto grid max-w-7xl gap-12 lg:grid-cols-[0.72fr_1.28fr] lg:gap-20">
        <div>
          <span className="grid h-12 w-12 place-items-center rounded-2xl bg-primary-wash text-primary-ink">
            <LockKey size={24} weight="bold" aria-hidden />
          </span>
          <h2 className="mt-7 max-w-lg text-4xl font-semibold leading-[1.04] tracking-[-0.045em] text-text md:text-5xl">Your data, protected by design.</h2>
          <p className="mt-6 max-w-lg text-base leading-relaxed text-text/62">
            MyLeafy keeps school data, device storage, and community services understandable and separate.
          </p>
        </div>
        <div className="border-y border-black/[0.08]">
          {items.map((item) => {
            const Icon = item.icon;
            return (
              <div key={item.title} className="grid gap-4 border-b border-black/[0.08] py-6 last:border-b-0 sm:grid-cols-[52px_0.42fr_1fr] sm:items-center">
                <span className="grid h-11 w-11 place-items-center rounded-xl bg-primary-wash text-primary-ink">
                  <Icon size={21} weight="bold" aria-hidden />
                </span>
                <h3 className="text-base font-semibold text-text">{item.title}</h3>
                <p className="text-sm leading-relaxed text-text/58">{item.body}</p>
              </div>
            );
          })}
        </div>
      </ScrollReveal>
    </section>
  );
}

function FeaturesPage({ navigate }: { navigate: (href: string) => void }) {
  return (
    <>
      <CapabilityRail />

      <SectionShell
        id="product"
        eyebrow="Product"
        title="Built around the rhythm of campus life"
      >
        <div className="grid gap-4 md:grid-cols-2">
          {featureBands.map((item) => (
            <FeatureBandCard key={item.label} item={item} />
          ))}
        </div>
      </SectionShell>

      <FeatureImageShowcase />

      <section id="data" className="border-y border-black/10 bg-surface-high/70">
        <SectionShell
          eyebrow="Data"
          title="Data sources"
          flush
        >
          <DataBoundaryTable />
        </SectionShell>
      </section>

      <section id="community" className="bg-paper">
        <SectionShell
          eyebrow="Workflow"
          title="Daily paths"
          flush
        >
          <div className="grid gap-4 lg:grid-cols-3">
            {workflowCards.map((item) => (
              <WorkflowCard key={item.title} item={item} />
            ))}
          </div>
        </SectionShell>
      </section>

      <ResourcesSection navigate={navigate} />
    </>
  );
}

function CapabilityRail() {
  return (
    <section className="border-b border-black/10 bg-white/80 py-3 backdrop-blur">
      <div className="leafy-scrollbar-none mx-auto flex max-w-7xl gap-3 overflow-x-auto px-4 md:px-6">
        {capabilityStats.map((metric) => (
          <div
            key={metric.label}
            className="flex min-w-52 items-center justify-between gap-7 rounded-lg border border-black/10 bg-paper/75 px-4 py-3"
          >
            <span className="text-sm font-medium text-text/60">{metric.label}</span>
            <span className="text-sm font-semibold text-text">{metric.value}</span>
          </div>
        ))}
      </div>
    </section>
  );
}

function FeatureImageShowcase() {
  return (
    <section id="screens" className="scroll-mt-24 border-y border-black/[0.06] bg-primary-soft">
      <div className="mx-auto max-w-7xl px-4 py-16 md:px-6 md:py-24">
        <div className="mb-12 max-w-4xl">
          <p className="text-sm font-semibold text-primary-ink">Inside the app</p>
          <h2 className="mt-4 text-4xl font-semibold leading-tight tracking-[-0.045em] text-text md:text-6xl">One focused place for campus routines.</h2>
          <p className="mt-5 max-w-[720px] text-base leading-relaxed text-text/64">
            Timetable, community, grades, credits, assessment, and timetable sharing.
          </p>
        </div>

        <div className="leafy-scrollbar-none -mx-4 flex snap-x snap-mandatory gap-5 overflow-x-auto px-4 pb-5 md:-mx-6 md:px-6">
          {featureShowcases.map((shot, index) => (
            <article
              key={shot.label}
              className="w-[min(82vw,340px)] shrink-0 snap-start overflow-hidden rounded-[28px] border border-black/[0.07] bg-white shadow-[0_18px_50px_rgba(16,32,24,0.07)]"
            >
              <div className="aspect-[941/2048] bg-primary-wash">
                <img
                  className="h-full w-full object-contain"
                  src={shot.image}
                  alt={shot.alt}
                  loading={index < 2 ? "eager" : "lazy"}
                  decoding="async"
                />
              </div>
              <div className="p-6">
                <p className="text-xs font-semibold text-primary-ink">{shot.label}</p>
                <h3 className="mt-2 text-2xl font-semibold leading-tight tracking-[-0.025em] text-text">{shot.title}</h3>
                <p className="mt-3 text-sm font-normal leading-relaxed text-text/62">{shot.body}</p>
              </div>
            </article>
          ))}
        </div>
      </div>
    </section>
  );
}

function FeatureBandCard({
  item
}: {
  item: {
    icon: IconComponent;
    label: string;
    title: string;
    body: string;
  };
}) {
  const Icon = item.icon;

  return (
    <article className="rounded-[24px] border border-black/[0.07] bg-white p-7 shadow-[0_18px_50px_rgba(16,32,24,0.055)]">
      <div className="mb-7 flex items-center justify-between gap-3">
        <span className="grid h-11 w-11 place-items-center rounded-2xl bg-primary-wash text-primary-ink">
          <Icon size={23} weight="bold" aria-hidden />
        </span>
        <span className="text-xs font-semibold text-primary-ink">{item.label}</span>
      </div>
      <h3 className="text-xl font-semibold leading-tight tracking-[-0.02em] text-text">{item.title}</h3>
      <p className="mt-4 text-sm font-normal leading-relaxed text-text/62">{item.body}</p>
    </article>
  );
}

function DataBoundaryTable() {
  return (
    <div className={ruleStackClass}>
      {homeDataBoundaries.map((item) => (
        <div key={item.label} className="grid gap-3 border-b border-black/10 px-5 py-6 last:border-b-0 md:grid-cols-[0.7fr_0.65fr_1.65fr] md:items-start">
          <p className="text-sm font-semibold text-text/60">{item.label}</p>
          <p className="text-sm font-semibold text-text">{item.value}</p>
          <p className="max-w-[72ch] text-sm font-normal leading-relaxed text-text/70">{item.body}</p>
        </div>
      ))}
    </div>
  );
}

function WorkflowCard({ item }: { item: { icon: IconComponent; title: string; body: string } }) {
  const Icon = item.icon;

  return (
    <article className="rounded-lg border border-black/10 bg-white/90 p-6 shadow-soft">
      <div className="grid h-11 w-11 place-items-center rounded-lg border border-black/10 bg-paper text-primary-ink">
        <Icon size={23} weight="bold" aria-hidden />
      </div>
      <h3 className="mt-7 text-2xl font-semibold leading-tight text-text">{item.title}</h3>
      <p className="mt-4 text-sm font-normal leading-relaxed text-text/70">{item.body}</p>
    </article>
  );
}

function ResourcesSection({ navigate }: { navigate: (href: string) => void }) {
  return (
    <section className="border-t border-black/10 bg-surface-high/70">
      <SectionShell
        eyebrow="Resources"
        title="Public support and App Store links"
        flush
      >
        <div className="grid gap-4 lg:grid-cols-[0.8fr_1.2fr]">
          <div className={featuredPanelClass}>
            <LockKey size={25} weight="bold" className="text-primary-ink" aria-hidden />
            <p className="mt-5 text-2xl font-semibold leading-tight text-text">Contact and policy links</p>
            <p className="mt-4 text-sm font-normal leading-relaxed text-text/70">
              Support: {site.supportEmail}. Privacy policy: {site.privacyUrl}.
            </p>
          </div>

          <div className="grid gap-4 md:grid-cols-3">
            {resourceLinks.map((link) => (
              <a
                key={link.title}
                href={link.href}
                onClick={(event) => {
                  event.preventDefault();
                  navigate(link.href);
                }}
                className="group rounded-lg border border-black/10 bg-white/90 p-5 shadow-soft transition-colors hover:bg-primary-soft"
              >
                <p className="text-sm font-semibold text-text/60">{link.title}</p>
                <p className="mt-3 min-h-24 text-sm font-normal leading-relaxed text-text/70">{link.body}</p>
                <span className="mt-5 inline-flex items-center gap-2 text-sm font-semibold text-primary-ink">
                  {link.cta}
                  <ArrowRight size={16} weight="bold" className="transition-transform group-hover:translate-x-1" aria-hidden />
                </span>
              </a>
            ))}
          </div>
        </div>

        <div className={`${ruleStackClass} mt-4`}>
          {appStoreLinks.map((link) => (
            <a
              key={link.label}
              href={link.value}
              onClick={(event) => {
                if (link.value.includes(site.domain)) {
                  event.preventDefault();
                  navigate(link.value);
                }
              }}
              className="group grid gap-2 border-b border-black/10 px-5 py-5 transition-colors last:border-b-0 hover:bg-primary-soft md:grid-cols-[0.9fr_1.4fr_auto] md:items-center"
            >
              <span className="text-sm font-semibold text-text/60">{link.label}</span>
              <span className="break-all text-sm font-medium text-text">{link.value}</span>
              <ArrowRight size={18} weight="bold" className="text-primary-ink transition-transform group-hover:translate-x-1" aria-hidden />
            </a>
          ))}
        </div>
      </SectionShell>
    </section>
  );
}

function SupportPage() {
  const mailto = `mailto:${site.supportEmail}?subject=MyLeafy Support`;

  return (
    <>
      <PageHero
        icon={Lifebuoy}
        label="Support"
        title="Support"
        body="For login, sync, timetable parsing, community, shared timetable, or rating issues, contact support by email or through in-app feedback."
      >
        <div className="mt-8 flex flex-col gap-3 sm:flex-row">
          <TapButton href={mailto} className={primaryButtonClass}>
            <EnvelopeSimple size={18} weight="bold" aria-hidden />
            Send email
          </TapButton>
          <CopyEmailButton email={site.supportEmail} />
        </div>
      </PageHero>

      <SectionShell eyebrow="Contact" title="Public contact" body="Email works for general support and privacy requests. In-app feedback is better for issues that need sync state, version, and device context.">
        <div className="grid gap-4 lg:grid-cols-[1.2fr_0.8fr]">
          <div className={panelClass}>
            <p className="text-sm font-semibold text-text/60">Support email</p>
            <a className="mt-3 block break-all text-3xl font-semibold leading-tight text-text hover:text-primary-ink" href={mailto}>
              {site.supportEmail}
            </a>
            <p className="mt-4 max-w-[68ch] text-sm font-normal leading-relaxed text-text/70">
              Use this address for App Store support, general feedback, feature requests, and privacy access, correction, or deletion requests.
            </p>
          </div>
          <div id="in-app" className={`${featuredPanelClass} scroll-mt-24`}>
            <CheckCircle size={24} weight="bold" className="text-primary-ink" aria-hidden />
            <p className="mt-4 text-xl font-semibold text-text">In-app feedback is better for diagnostics</p>
            <p className="mt-3 text-sm font-normal leading-relaxed text-text/70">
              In-app feedback can include device model, system version, app version, login state, and latest sync time.
            </p>
          </div>
        </div>
      </SectionShell>

      <SectionShell eyebrow="Before sending" title="Information to include">
        <NumberedList items={supportChecklist} />
      </SectionShell>

      <SectionShell eyebrow="Scope" title="Common support topics">
        <AsymmetricIconGrid items={supportTopics} />
      </SectionShell>
    </>
  );
}

function PrivacyPage() {
  return (
    <>
      <PageHero
        icon={ShieldCheck}
        label="Privacy"
        title="Privacy Policy"
        body={`This policy explains how MyLeafy handles school login, local cache, community, feedback, ratings, shared timetable, and website data. Last updated: ${site.updatedAt}.`}
      >
        <div className="mt-8 flex flex-col gap-3 sm:flex-row">
          <TapButton href="#privacy-rights" className={primaryButtonClass}>
            <LockKey size={18} weight="bold" aria-hidden />
            View privacy choices
          </TapButton>
          <TapButton href={`mailto:${site.supportEmail}?subject=MyLeafy Privacy Request`} className={secondaryButtonClass}>
            <EnvelopeSimple size={18} weight="bold" aria-hidden />
            Send privacy request
          </TapButton>
        </div>
      </PageHero>

      <SectionShell eyebrow="Quick read" title="Four things to know">
        <AsymmetricIconGrid items={privacySummaryCards} />
      </SectionShell>

      <article className="mx-auto max-w-5xl px-4 py-14 md:px-6">
        <div className={ruleStackClass}>
          {privacySections.map((section) => (
            <PrivacySection key={section.title} section={section} />
          ))}
        </div>
      </article>
    </>
  );
}

function ShareTimetablePage({ code }: { code: string }) {
  const [copied, setCopied] = useState(false);
  const normalizedCode = code.toUpperCase().replace(/[^A-Z2-7]/g, "");

  async function copyCode() {
    await navigator.clipboard?.writeText(normalizedCode);
    setCopied(true);
    window.setTimeout(() => setCopied(false), 1800);
  }

  return (
    <>
      <PageHero
        icon={CalendarBlank}
        label="Shared timetable"
        title="Shared timetable invite"
        body="Copy the invite code, then open MyLeafy and accept it from Profile -> Shared Timetable -> +."
      >
        <div className="mt-8 grid max-w-xl gap-4">
          <div className={featuredPanelClass}>
            <p className="text-sm font-semibold text-text/60">Invite code</p>
            <p className="mt-3 break-all text-5xl font-semibold tracking-normal text-text">{normalizedCode || "Not recognized"}</p>
            <p className="mt-4 text-sm font-normal leading-relaxed text-text/70">
              Invite codes are valid for seven days and can be accepted by one person. Access can be revoked later.
            </p>
          </div>
          <button type="button" onClick={copyCode} className={`${primaryButtonClass} inline-flex min-h-11 w-fit items-center gap-2 rounded-lg px-5 text-sm font-medium`}>
            <CheckCircle size={18} weight="bold" aria-hidden />
            {copied ? "Copied" : "Copy invite code"}
          </button>
        </div>
      </PageHero>

      <SectionShell eyebrow="Accept" title="Accept in the app">
        <NumberedList items={["Open MyLeafy.", "Go to Profile -> Shared Timetable.", "Tap + in the top-right corner.", "Paste the invite code and accept it."]} />
      </SectionShell>
    </>
  );
}

function ShareCommunityPostPage({ postID }: { postID: string }) {
  const normalizedPostID = postID.match(/^[0-9a-fA-F-]{36}$/) ? postID : "";
  const appURL = normalizedPostID ? `https://${site.domain}/share/community/post/${normalizedPostID}?open=1` : site.homeUrl;

  return (
    <>
      <PageHero
        icon={ChatsCircle}
        label="Community post"
        title="MyLeafy community post"
        body="This is a MyLeafy community share link. If the latest app is installed, it opens the post detail directly."
      >
        <div className="mt-8 flex flex-col gap-3 sm:flex-row">
          <TapButton href={appURL} className={primaryButtonClass}>
            <DeviceMobile size={18} weight="bold" aria-hidden />
            Open MyLeafy
          </TapButton>
          <TapButton href={site.appStoreUrl || site.supportUrl} className={secondaryButtonClass}>
            <ArrowRight size={18} weight="bold" aria-hidden />
            Get or update MyLeafy
          </TapButton>
        </div>
      </PageHero>

      <SectionShell eyebrow="Privacy" title="Community content opens in the app">
        <NumberedList
          items={[
            "Share cards may show the post title and a short summary. Comments stay in the app.",
            "After signing in to MyLeafy, the app opens the post detail.",
            "If the app opens but does not show the post, update MyLeafy and try again.",
            "If the post has been deleted or is no longer visible, the app will show that it cannot be opened."
          ]}
        />
      </SectionShell>
    </>
  );
}

function PageHero({
  icon: Icon,
  label,
  title,
  body,
  children
}: {
  icon: IconComponent;
  label: string;
  title: string;
  body: string;
  children?: ReactNode;
}) {
  return (
    <section className="relative isolate overflow-hidden border-b border-black/[0.06] bg-primary-soft">
      <div className="absolute -right-24 -top-40 -z-10 h-[520px] w-[520px] rounded-full bg-primary-wash" aria-hidden />
      <div className="mx-auto grid max-w-7xl gap-10 px-4 py-16 md:px-6 lg:grid-cols-[0.42fr_1.58fr] lg:py-24">
        <div>
          <div className="inline-grid h-12 w-12 place-items-center rounded-2xl border border-primary/10 bg-white text-primary-ink shadow-soft">
            <Icon size={24} weight="bold" aria-hidden />
          </div>
        </div>
        <div>
          <p className="text-sm font-semibold text-primary-ink">{label}</p>
          <h1 className="mt-4 text-5xl font-semibold leading-none tracking-[-0.05em] text-text md:text-7xl">{title}</h1>
          <p className="mt-6 max-w-[76ch] text-lg font-normal leading-relaxed text-text/64">{body}</p>
          {children}
        </div>
      </div>
    </section>
  );
}

function SectionShell({
  eyebrow,
  title,
  body,
  children,
  id,
  flush = false
}: {
  eyebrow: string;
  title: string;
  body?: string;
  children: ReactNode;
  id?: string;
  flush?: boolean;
}) {
  return (
    <section id={id} className={`${flush ? "" : "mx-auto max-w-7xl"} scroll-mt-24 px-4 py-14 md:px-6 md:py-20`}>
      <div className="mx-auto mb-9 grid max-w-7xl gap-4 md:grid-cols-[0.52fr_1.48fr] md:items-end">
        <p className="text-sm font-semibold uppercase text-primary-ink">{eyebrow}</p>
        <div>
          <h2 className="max-w-4xl text-4xl font-semibold leading-tight tracking-normal text-text md:text-6xl">{title}</h2>
          {body && <p className="mt-5 max-w-[760px] text-base font-normal leading-relaxed text-text/70">{body}</p>}
        </div>
      </div>
      <div className="mx-auto max-w-7xl">{children}</div>
    </section>
  );
}

function NumberedList({ items }: { items: string[] }) {
  return (
    <div className={ruleStackClass}>
      {items.map((item, index) => (
        <div key={item} className="grid grid-cols-[48px_1fr] gap-4 border-b border-black/10 px-5 py-5 last:border-b-0">
          <span className="text-sm font-semibold text-primary-ink">{String(index + 1).padStart(2, "0")}</span>
          <p className="text-sm font-normal leading-relaxed text-text/70">{item}</p>
        </div>
      ))}
    </div>
  );
}

function AsymmetricIconGrid({ items }: { items: Array<{ icon: IconComponent; title: string; body: string }> }) {
  return (
    <div className="grid gap-4 lg:grid-cols-2">
      {items.map((item) => {
        const Icon = item.icon;

        return (
          <article key={item.title} className={panelClass}>
            <div className="grid h-11 w-11 place-items-center rounded-lg border border-primary/20 bg-primary-wash text-primary-ink">
              <Icon size={23} weight="bold" aria-hidden />
            </div>
            <h3 className="mt-6 text-xl font-semibold text-text">{item.title}</h3>
            <p className="mt-3 max-w-[68ch] text-sm font-normal leading-relaxed text-text/70">{item.body}</p>
          </article>
        );
      })}
    </div>
  );
}

function PrivacySection({
  section
}: {
  section: {
    id?: string;
    title: string;
    icon: IconComponent;
    items: string[];
  };
}) {
  const Icon = section.icon;

  return (
    <section id={section.id} className="grid scroll-mt-24 gap-6 border-b border-black/10 px-5 py-8 last:border-b-0 md:grid-cols-[0.42fr_1fr]">
      <div className="flex items-center gap-3 md:items-start">
        <span className="grid h-10 w-10 shrink-0 place-items-center rounded-lg border border-primary/20 bg-primary-wash text-primary-ink">
          <Icon size={21} weight="bold" aria-hidden />
        </span>
        <h2 className="text-2xl font-semibold leading-tight text-text">{section.title}</h2>
      </div>
      <div className="space-y-4">
        {section.items.map((item) => (
          <p key={item} className="text-sm font-normal leading-relaxed text-text/70">
            {item}
          </p>
        ))}
      </div>
    </section>
  );
}

function Footer({ navigate }: { navigate: (href: string) => void }) {
  return (
    <footer className="border-t border-black/10 bg-white/80">
      <div className="mx-auto grid max-w-7xl gap-10 px-4 py-12 md:px-6 lg:grid-cols-[1.05fr_1.95fr]">
        <div>
          <div className="flex items-center gap-3">
            <img className="h-10 w-10 rounded-lg border border-black/10 shadow-soft" src="/app-icon.png" alt="MyLeafy app icon" />
            <div>
              <p className="text-xl font-semibold leading-none text-text">MyLeafy</p>
              <p className="mt-1 text-sm font-medium text-text/60">BJFU campus tool</p>
            </div>
          </div>
          <p className="mt-6 max-w-[64ch] text-sm font-normal leading-relaxed text-text/60">
            Currently supports Beijing Forestry University. Support: {site.supportEmail}.
          </p>
          <a
            href={`mailto:${site.supportEmail}`}
            className="mt-6 inline-flex min-h-11 items-center gap-2 rounded-lg border border-black/10 bg-paper px-4 text-sm font-semibold text-text transition-colors hover:bg-primary-soft"
          >
            <EnvelopeSimple size={17} weight="bold" aria-hidden />
            {site.supportEmail}
          </a>
        </div>

        <nav className="grid gap-8 sm:grid-cols-2 lg:grid-cols-4">
          {footerGroups.map((group) => (
            <div key={group.title}>
              <h2 className="text-sm font-semibold text-text">{group.title}</h2>
              <div className="mt-4 grid gap-3">
                {group.links.map((link) => (
                  <a
                    key={`${group.title}-${link.label}`}
                    href={link.href}
                    onClick={(event) => {
                      if (link.href.startsWith("http") && !link.href.includes(site.domain)) {
                        return;
                      }
                      if (link.href.startsWith("mailto:")) {
                        return;
                      }
                      event.preventDefault();
                      navigate(link.href);
                    }}
                    className="break-words text-sm font-medium leading-relaxed text-text/60 hover:text-primary-ink"
                  >
                    {link.label}
                  </a>
                ))}
              </div>
            </div>
          ))}
        </nav>
      </div>
      <div className="border-t border-black/10 px-4 py-4 md:px-6">
        <div className="mx-auto flex max-w-7xl flex-col gap-2 text-xs font-medium text-text/60 md:flex-row md:items-center md:justify-between">
          <span>Last updated: {site.updatedAt}</span>
          <div className="flex flex-wrap gap-x-5 gap-y-2">
            <a
              className="inline-flex items-center gap-2 hover:text-primary-ink"
              href="/"
              onClick={(event) => {
                event.preventDefault();
                navigate("/");
              }}
            >
              <House size={15} aria-hidden />
              Home
            </a>
            <a className="inline-flex items-center gap-2 hover:text-primary-ink" href={`mailto:${site.supportEmail}`}>
              <EnvelopeSimple size={15} aria-hidden />
              Contact
            </a>
          </div>
        </div>
      </div>
    </footer>
  );
}
