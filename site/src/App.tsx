import { lazy, Suspense, useEffect, useState } from "react";
import type { ReactNode } from "react";
import {
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
  Headset,
  House,
  List,
  LockKey,
  ShieldCheck,
  X
} from "@phosphor-icons/react";
import {
  appStoreLinks,
  appScreenshots,
  capabilityStats,
  featureBands,
  featureShowcases,
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

const primaryButtonClass =
  "border border-accent bg-accent text-forest shadow-accent hover:border-accent-strong hover:bg-accent-strong";
const secondaryButtonClass =
  "border border-white/20 bg-forest-elevated/80 text-ivory shadow-deep backdrop-blur-xl hover:border-white/30 hover:bg-forest-elevated";
const panelClass =
  "rounded-[24px] border border-white/10 bg-forest-elevated/80 p-6 shadow-deep backdrop-blur-xl";
const featuredPanelClass =
  "rounded-[24px] border border-accent/25 bg-accent-muted/50 p-6 shadow-deep";
const ruleStackClass =
  "overflow-hidden rounded-[24px] border border-white/10 bg-forest-elevated/70 shadow-deep";

function normalizedPath(pathname: string) {
  if (pathname === "/") return "/";
  return pathname.replace(/\/+$/, "");
}

function routeFromHref(href: string) {
  if (href.startsWith("mailto:")) return href;

  try {
    const url = new URL(href, window.location.origin);
    return normalizedPath(url.pathname) + url.hash;
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
    window.history.pushState({}, "", targetPath + (hash ? "#" + hash : ""));
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
    <div className="public-site min-h-[100dvh] bg-paper text-text">
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
  const [menuOpen, setMenuOpen] = useState(false);

  useEffect(() => setMenuOpen(false), [activePath]);

  function go(href: string) {
    setMenuOpen(false);
    navigate(href);
  }

  return (
    <header className="fixed top-0 z-40 w-full px-3 pt-3 md:px-5 md:pt-4">
      <div className="mx-auto flex h-16 max-w-7xl items-center rounded-full border border-white/10 bg-forest/80 px-4 shadow-deep backdrop-blur-2xl md:px-5">
        <a
          href="/"
          onClick={(event) => {
            event.preventDefault();
            go("/");
          }}
          className="leafy-pressable flex min-w-fit items-center gap-3 rounded-full"
          aria-label="MyLeafy home"
        >
          <img className="h-9 w-9 rounded-[11px] border border-white/10 shadow-deep" src="/app-icon.png" alt="MyLeafy app icon" />
          <strong className="text-lg font-semibold leading-none tracking-[-0.025em] text-ivory">MyLeafy</strong>
        </a>

        <nav className="ml-8 hidden flex-1 items-center justify-center gap-1 md:flex">
          {navItems.map((item) => {
            const route = routeFromHref(item.href).split("#")[0];
            const isActive = route === "/" ? activePath === "/" : activePath === route;
            return (
              <a
                key={item.href}
                href={item.href}
                onClick={(event) => {
                  event.preventDefault();
                  go(item.href);
                }}
                className={
                  "leafy-pressable whitespace-nowrap rounded-full px-4 py-2 text-sm font-medium transition-colors " +
                  (isActive ? "bg-white/10 text-ivory" : "text-ivory/60 hover:bg-white/[0.07] hover:text-ivory")
                }
              >
                {item.label}
              </a>
            );
          })}
        </nav>

        <div className="ml-auto flex items-center gap-2">
          <a
            href={"mailto:" + site.supportEmail}
            className="leafy-pressable hidden rounded-full px-3 py-2 text-sm font-medium text-ivory/60 hover:bg-white/[0.07] hover:text-ivory lg:inline-flex"
          >
            Contact
          </a>
          <div className="hidden sm:block">
            <AppStoreBadge compact />
          </div>
          <button
            type="button"
            className="leafy-pressable grid h-11 w-11 place-items-center rounded-full border border-white/10 bg-white/[0.06] text-ivory md:hidden"
            aria-label={menuOpen ? "Close navigation menu" : "Open navigation menu"}
            aria-expanded={menuOpen}
            onClick={() => setMenuOpen((value) => !value)}
          >
            {menuOpen ? <X size={21} weight="bold" aria-hidden /> : <List size={21} weight="bold" aria-hidden />}
          </button>
        </div>
      </div>

      {menuOpen && (
        <nav className="mx-auto mt-2 grid max-w-7xl gap-1 rounded-[24px] border border-white/10 bg-forest/95 p-3 shadow-deep backdrop-blur-2xl md:hidden">
          {navItems.map((item) => (
            <a
              key={item.href}
              href={item.href}
              onClick={(event) => {
                event.preventDefault();
                go(item.href);
              }}
              className="leafy-pressable rounded-2xl px-4 py-3 text-sm font-medium text-ivory/80 hover:bg-white/[0.07] hover:text-ivory"
            >
              {item.label}
            </a>
          ))}
          <a className="leafy-pressable rounded-2xl px-4 py-3 text-sm font-medium text-accent" href={"mailto:" + site.supportEmail}>
            Contact support
          </a>
        </nav>
      )}
    </header>
  );
}

function HomePage({ navigate }: { navigate: (href: string) => void }) {
  return (
    <>
      <section className="hero-canvas relative isolate flex min-h-[100dvh] items-end overflow-hidden pt-24 lg:min-h-[760px]">
        <img
          className="absolute inset-0 -z-20 h-full w-full object-cover object-[48%_center]"
          src="/media/campus/rainy-woodland-path.jpg"
          alt=""
          aria-hidden
          decoding="async"
        />
        <div className="hero-scrim absolute inset-0 -z-10" aria-hidden />
        <div className="mx-auto grid w-full max-w-7xl items-end gap-8 px-4 pb-10 md:px-6 md:pb-14 lg:grid-cols-[0.88fr_1.12fr] lg:gap-4">
          <StaggerReveal className="relative z-10 max-w-xl pb-4 lg:pb-12">
            <p className="mb-5 text-sm font-semibold text-accent">Built for BJFU students</p>
            <h1 className="max-w-[720px] text-[clamp(3.4rem,7vw,6.6rem)] font-semibold leading-[0.91] tracking-[-0.065em] text-ivory">
              Campus life,<br />in one place.
            </h1>
            <p className="mt-6 max-w-[500px] text-base leading-relaxed text-ivory/70 md:text-lg">
              Timetable, academics, community, and campus answers in one focused iPhone app.
            </p>
            <div className="mt-8 flex flex-col gap-3 sm:flex-row">
              <AppStoreBadge />
              <TapButton onClick={() => navigate("/features")} className={secondaryButtonClass + " px-5 text-[15px] font-semibold"}>
                Explore features
                <ArrowRight size={17} weight="bold" aria-hidden />
              </TapButton>
            </div>
          </StaggerReveal>

          <HeroPhones />
        </div>
      </section>

      <CampusIdentitySection />
      <AppExperienceSection />
      <CampusSeasonsSection />
      <HomeDataTrust />

      <section className="relative isolate overflow-hidden px-4 py-24 md:px-6 md:py-32">
        <img
          className="absolute inset-0 -z-20 h-full w-full object-cover"
          src="/media/campus/campus-skyline-dusk.jpg"
          alt=""
          aria-hidden
          loading="lazy"
          decoding="async"
        />
        <div className="absolute inset-0 -z-10 bg-forest/90" aria-hidden />
        <ScrollReveal className="mx-auto flex max-w-7xl flex-col items-start justify-between gap-9 md:flex-row md:items-end">
          <div className="max-w-3xl">
            <img className="h-16 w-16 rounded-[18px] border border-white/10 shadow-deep" src="/app-icon.png" alt="MyLeafy app icon" />
            <h2 className="mt-8 text-4xl font-semibold leading-[0.98] tracking-[-0.045em] text-ivory md:text-6xl">
              Your campus day,<br />within reach.
            </h2>
            <p className="mt-5 max-w-xl text-base leading-relaxed text-ivory/60">
              Open MyLeafy and start with the week in front of you.
            </p>
          </div>
          <AppStoreBadge />
        </ScrollReveal>
      </section>
    </>
  );
}

function AppStoreBadge({ compact = false }: { compact?: boolean }) {
  return (
    <a
      href={site.appStoreUrl}
      className={"app-store-badge leafy-pressable inline-flex shrink-0 " + (compact ? "h-10" : "h-12")}
      aria-label="Download MyLeafy on the App Store"
    >
      <img className="h-full w-auto max-w-none" src="/media/download-on-the-app-store.svg" alt="Download on the App Store" />
    </a>
  );
}

function PhoneFrame({
  image,
  alt,
  className = "",
  loading = "eager"
}: {
  image: string;
  alt: string;
  className?: string;
  loading?: "eager" | "lazy";
}) {
  return (
    <div className={"phone-frame relative aspect-[1350/2760] " + className}>
      <div className="phone-screen absolute overflow-hidden bg-forest">
        <img className="h-full w-full bg-white object-fill" src={image} alt={alt} loading={loading} decoding="async" />
      </div>
      <img
        className="pointer-events-none absolute inset-0 h-full w-full max-w-none"
        src="/media/iphone-17-pro-silver-portrait.png"
        alt=""
        aria-hidden
        loading={loading}
        decoding="async"
      />
    </div>
  );
}

function HeroPhones() {
  return (
    <div className="relative mx-auto min-h-[500px] w-full max-w-[650px] sm:min-h-[590px] lg:min-h-[650px]" aria-label="MyLeafy app previews">
      <div className="hero-phone absolute bottom-0 left-[3%] z-10 w-[min(48vw,292px)]">
        <PhoneFrame image={appScreenshots[0].image} alt={appScreenshots[0].alt} />
      </div>
      <div className="hero-phone absolute bottom-[-8%] right-[4%] w-[min(48vw,292px)]">
        <PhoneFrame image={appScreenshots[1].image} alt={appScreenshots[1].alt} />
      </div>
    </div>
  );
}

function CampusIdentitySection() {
  return (
    <section className="bg-paper px-4 py-16 md:px-6 md:py-20">
      <ScrollReveal className="mx-auto grid max-w-7xl gap-8 lg:grid-cols-[0.65fr_1.35fr] lg:items-end">
        <div className="lg:order-2">
          <div className="overflow-hidden rounded-[28px] border border-white/10 bg-forest-elevated shadow-deep">
            <img
              className="aspect-[16/9] h-full w-full object-cover"
              src="/media/campus/classroom-at-dusk.jpg"
              alt="A quiet BJFU classroom framed by evening windows"
              loading="lazy"
              decoding="async"
            />
          </div>
        </div>
        <div className="grid gap-8 lg:order-1 lg:pb-5">
          <div>
            <h2 className="max-w-xl text-4xl font-semibold leading-[1.02] tracking-[-0.045em] text-ivory md:text-5xl">
              Made from the life already happening here.
            </h2>
            <p className="mt-5 max-w-lg text-base leading-relaxed text-ivory/60">
              MyLeafy brings school systems and everyday campus routines into one calmer experience.
            </p>
          </div>
          <div className="overflow-hidden rounded-[24px] border border-white/10 shadow-deep">
            <img
              className="aspect-[3/2] w-full object-cover"
              src="/media/campus/campus-entrance-bicycles.jpg"
              alt="Bicycles beside a stone lion at a BJFU campus entrance"
              loading="lazy"
              decoding="async"
            />
          </div>
        </div>
      </ScrollReveal>
    </section>
  );
}

function AppExperienceSection() {
  const items = [
    { icon: CalendarBlank, title: "Timetable first", body: "See the current week, classes, rooms, reminders, and exams at a glance." },
    { icon: GraduationCap, title: "Academics together", body: "Grades, plans, credits, classrooms, and the academic calendar stay organized." },
    { icon: ChatsCircle, title: "Community separate", body: "Campus posts and notices have their own space, away from school login data." }
  ];

  return (
    <section className="overflow-hidden border-y border-white/[0.07] bg-forest-low px-4 py-24 md:px-6 md:py-36">
      <div className="mx-auto max-w-7xl">
        <ScrollReveal className="max-w-3xl">
          <p className="text-sm font-semibold text-accent">Inside MyLeafy</p>
          <h2 className="mt-5 text-4xl font-semibold leading-[1] tracking-[-0.05em] text-ivory md:text-6xl">
            The week comes first.<br />Everything else stays close.
          </h2>
        </ScrollReveal>

        <div className="mt-16 grid gap-12 lg:grid-cols-[0.7fr_1.3fr] lg:items-center">
          <div className="border-t border-white/10">
            {items.map((item) => {
              const Icon = item.icon;
              return (
                <ScrollReveal key={item.title} className="grid grid-cols-[44px_1fr] gap-4 border-b border-white/10 py-6">
                  <span className="grid h-10 w-10 place-items-center rounded-xl bg-accent-muted text-accent">
                    <Icon size={20} weight="bold" aria-hidden />
                  </span>
                  <div>
                    <h3 className="text-base font-semibold text-ivory">{item.title}</h3>
                    <p className="mt-2 text-sm leading-relaxed text-ivory/60">{item.body}</p>
                  </div>
                </ScrollReveal>
              );
            })}
          </div>

          <ScrollReveal className="leafy-scrollbar-none -mx-4 flex snap-x snap-mandatory gap-5 overflow-x-auto px-4 pb-6 md:-mx-6 md:px-6 lg:mx-0 lg:px-0">
            {appScreenshots.slice(0, 3).map((shot, index) => (
              <div
                key={shot.label}
                className={"shrink-0 snap-center " + (index === 1 ? "mt-14 w-[min(62vw,260px)]" : "w-[min(62vw,285px)]")}
              >
                <PhoneFrame image={shot.image} alt={shot.alt} loading={index === 0 ? "eager" : "lazy"} />
              </div>
            ))}
          </ScrollReveal>
        </div>
      </div>
    </section>
  );
}

function CampusSeasonsSection() {
  return (
    <section className="bg-paper px-4 py-24 md:px-6 md:py-36">
      <div className="mx-auto max-w-7xl">
        <ScrollReveal className="max-w-3xl">
          <h2 className="text-4xl font-semibold leading-[1.02] tracking-[-0.045em] text-ivory md:text-6xl">
            One campus, through every season.
          </h2>
          <p className="mt-5 max-w-xl text-base leading-relaxed text-ivory/60">
            The tools stay consistent while the campus around them keeps changing.
          </p>
        </ScrollReveal>

        <div className="mt-14 grid gap-5 md:grid-cols-[1.08fr_0.92fr] md:grid-rows-2">
          <ScrollReveal className="overflow-hidden rounded-[28px] border border-white/10 md:row-span-2">
            <img
              className="h-full min-h-[520px] w-full object-cover"
              src="/media/campus/autumn-campus-canopy.jpg"
              alt="Golden autumn trees framing a BJFU campus building"
              loading="lazy"
              decoding="async"
            />
          </ScrollReveal>
          <ScrollReveal className="overflow-hidden rounded-[28px] border border-white/10">
            <img
              className="aspect-[16/10] h-full w-full object-cover object-[center_70%]"
              src="/media/campus/spring-blossoms-cat.jpg"
              alt="A campus cat under spring blossoms at BJFU"
              loading="lazy"
              decoding="async"
            />
          </ScrollReveal>
          <ScrollReveal className="overflow-hidden rounded-[28px] border border-white/10">
            <img
              className="aspect-[16/10] h-full w-full object-cover object-[center_58%]"
              src="/media/campus/snowy-campus-building.jpg"
              alt="A BJFU campus building surrounded by snow-covered trees"
              loading="lazy"
              decoding="async"
            />
          </ScrollReveal>
        </div>
      </div>
    </section>
  );
}

function HomeDataTrust() {
  const icons = [Buildings, Database, CloudCheck, ShieldCheck];

  return (
    <section className="border-t border-white/[0.07] bg-forest-low px-4 py-24 md:px-6 md:py-32">
      <ScrollReveal className="mx-auto grid max-w-7xl gap-14 lg:grid-cols-[0.72fr_1.28fr] lg:gap-24">
        <div>
          <span className="grid h-12 w-12 place-items-center rounded-2xl bg-accent-muted text-accent">
            <LockKey size={24} weight="bold" aria-hidden />
          </span>
          <h2 className="mt-8 max-w-lg text-4xl font-semibold leading-[1.02] tracking-[-0.045em] text-ivory md:text-5xl">
            Clear boundaries for every kind of data.
          </h2>
          <p className="mt-5 max-w-md text-base leading-relaxed text-ivory/60">
            School data, local storage, community services, and the public website remain understandable and separate.
          </p>
        </div>
        <div className="grid gap-x-10 gap-y-9 sm:grid-cols-2">
          {homeDataBoundaries.map((item, index) => {
            const Icon = icons[index] ?? ShieldCheck;
            return (
              <div key={item.label} className="border-t border-white/10 pt-5">
                <Icon size={22} weight="bold" className="text-accent" aria-hidden />
                <p className="mt-5 text-sm font-semibold text-ivory/50">{item.label}</p>
                <h3 className="mt-2 text-2xl font-semibold tracking-[-0.025em] text-ivory">{item.value}</h3>
                <p className="mt-3 text-sm leading-relaxed text-ivory/50">{item.body}</p>
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
      <section className="relative isolate overflow-hidden px-4 pb-20 pt-32 md:px-6 md:pb-28 md:pt-40">
        <img
          className="absolute inset-0 -z-20 h-full w-full object-cover object-[center_54%]"
          src="/media/campus/autumn-campus-canopy.jpg"
          alt=""
          aria-hidden
          decoding="async"
        />
        <div className="hero-scrim absolute inset-0 -z-10" aria-hidden />
        <div className="mx-auto grid max-w-7xl gap-12 lg:grid-cols-[1fr_0.7fr] lg:items-end">
          <StaggerReveal className="max-w-3xl">
            <p className="text-sm font-semibold text-accent">Features</p>
            <h1 className="mt-5 text-[clamp(3.4rem,7vw,6.4rem)] font-semibold leading-[0.92] tracking-[-0.06em] text-ivory">
              Built around<br />campus rhythm.
            </h1>
            <p className="mt-6 max-w-xl text-base leading-relaxed text-ivory/70 md:text-lg">
              From the first class to the last campus notice, MyLeafy keeps the day clear.
            </p>
          </StaggerReveal>
          <div className="mx-auto w-[min(58vw,285px)] lg:mr-12">
            <PhoneFrame image={appScreenshots[2].image} alt={appScreenshots[2].alt} />
          </div>
        </div>
      </section>

      <CapabilityRail />

      <SectionShell id="product" title="Four spaces, one daily flow" body="Each part has a clear job, so the app stays easy to scan.">
        <FeatureBandList />
      </SectionShell>

      <FeatureImageShowcase />

      <section id="data" className="scroll-mt-24 border-y border-white/[0.07] bg-forest-low">
        <SectionShell title="Where your data lives" body="The source and purpose of each data group remain visible.">
          <DataBoundaryTable />
        </SectionShell>
      </section>

      <section id="community" className="scroll-mt-24 bg-paper">
        <SectionShell title="Designed for frequent checks">
          <WorkflowList />
        </SectionShell>
      </section>

      <ResourcesSection navigate={navigate} />
    </>
  );
}

function CapabilityRail() {
  return (
    <section className="border-y border-white/[0.07] bg-forest">
      <div className="leafy-scrollbar-none mx-auto flex max-w-7xl overflow-x-auto px-4 md:px-6">
        {capabilityStats.map((metric) => (
          <div key={metric.label} className="min-w-[220px] flex-1 border-r border-white/[0.08] px-5 py-7 first:pl-0 last:border-r-0 last:pr-0">
            <span className="block text-xs font-medium text-ivory/40">{metric.label}</span>
            <span className="mt-2 block text-sm font-semibold text-ivory">{metric.value}</span>
          </div>
        ))}
      </div>
    </section>
  );
}

function FeatureBandList() {
  return (
    <div className="grid gap-x-10 gap-y-0 lg:grid-cols-2">
      {featureBands.map((item) => {
        const Icon = item.icon;
        return (
          <ScrollReveal key={item.label} className="grid grid-cols-[48px_1fr] gap-5 border-t border-white/10 py-8">
            <span className="grid h-11 w-11 place-items-center rounded-xl bg-accent-muted text-accent">
              <Icon size={22} weight="bold" aria-hidden />
            </span>
            <div>
              <p className="text-sm font-semibold text-accent">{item.label}</p>
              <h3 className="mt-3 text-2xl font-semibold leading-tight tracking-[-0.025em] text-ivory">{item.title}</h3>
              <p className="mt-3 max-w-xl text-sm leading-relaxed text-ivory/60">{item.body}</p>
            </div>
          </ScrollReveal>
        );
      })}
    </div>
  );
}

function FeatureImageShowcase() {
  return (
    <section id="screens" className="scroll-mt-24 overflow-hidden border-y border-white/[0.07] bg-forest-low py-24 md:py-32">
      <div className="mx-auto max-w-7xl px-4 md:px-6">
        <ScrollReveal className="max-w-3xl">
          <p className="text-sm font-semibold text-accent">Inside the app</p>
          <h2 className="mt-5 text-4xl font-semibold leading-[1] tracking-[-0.05em] text-ivory md:text-6xl">
            A focused view for every routine.
          </h2>
          <p className="mt-5 max-w-xl text-base leading-relaxed text-ivory/60">
            Timetable, community, grades, study materials, campus information, and Leafy AI.
          </p>
        </ScrollReveal>
      </div>

      <div className="leafy-scrollbar-none mt-14 flex snap-x snap-mandatory gap-5 overflow-x-auto px-[max(1rem,calc((100vw-80rem)/2))] pb-7 md:gap-7">
        {featureShowcases.map((shot, index) => (
          <article key={shot.label} className="w-[min(82vw,340px)] shrink-0 snap-start">
            <div className="flex min-h-[590px] items-center justify-center rounded-[28px] border border-white/10 bg-forest p-6 shadow-deep">
              <PhoneFrame image={shot.image} alt={shot.alt} className="w-[84%]" loading={index < 2 ? "eager" : "lazy"} />
            </div>
            <p className="mt-5 text-sm font-semibold text-accent">{shot.label}</p>
            <h3 className="mt-2 text-2xl font-semibold leading-tight tracking-[-0.025em] text-ivory">{shot.title}</h3>
            <p className="mt-3 text-sm leading-relaxed text-ivory/50">{shot.body}</p>
          </article>
        ))}
      </div>
    </section>
  );
}

function DataBoundaryTable() {
  return (
    <div className="grid gap-5 md:grid-cols-2">
      {homeDataBoundaries.map((item) => (
        <div key={item.label} className="rounded-[24px] border border-white/10 bg-forest-elevated/60 p-6">
          <p className="text-sm font-semibold text-accent">{item.label}</p>
          <h3 className="mt-4 text-3xl font-semibold tracking-[-0.03em] text-ivory">{item.value}</h3>
          <p className="mt-4 text-sm leading-relaxed text-ivory/60">{item.body}</p>
        </div>
      ))}
    </div>
  );
}

function WorkflowList() {
  return (
    <div className="grid gap-12 lg:grid-cols-[0.7fr_1.3fr]">
      <div className="overflow-hidden rounded-[28px] border border-white/10">
        <img
          className="h-full min-h-[430px] w-full object-cover"
          src="/media/campus/campus-entrance-bicycles.jpg"
          alt="Bicycles parked beside a BJFU campus entrance"
          loading="lazy"
          decoding="async"
        />
      </div>
      <div className="border-t border-white/10">
        {workflowCards.map((item) => {
          const Icon = item.icon;
          return (
            <div key={item.title} className="grid grid-cols-[48px_1fr] gap-5 border-b border-white/10 py-7">
              <span className="grid h-11 w-11 place-items-center rounded-xl bg-accent-muted text-accent">
                <Icon size={22} weight="bold" aria-hidden />
              </span>
              <div>
                <h3 className="text-2xl font-semibold tracking-[-0.025em] text-ivory">{item.title}</h3>
                <p className="mt-3 max-w-2xl text-sm leading-relaxed text-ivory/60">{item.body}</p>
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}

function ResourcesSection({ navigate }: { navigate: (href: string) => void }) {
  return (
    <section className="border-t border-white/[0.07] bg-paper">
      <SectionShell title="Support and public links">
        <div className="grid gap-5 lg:grid-cols-[0.74fr_1.26fr]">
          <div className={featuredPanelClass}>
            <LockKey size={25} weight="bold" className="text-accent" aria-hidden />
            <p className="mt-6 text-2xl font-semibold leading-tight text-ivory">Contact and policy links</p>
            <p className="mt-4 text-sm leading-relaxed text-ivory/60">
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
                className="group rounded-[24px] border border-white/10 bg-forest-elevated/70 p-5 transition-colors hover:border-accent/30 hover:bg-forest-elevated"
              >
                <p className="text-sm font-semibold text-ivory/50">{link.title}</p>
                <p className="mt-4 min-h-24 text-sm leading-relaxed text-ivory/60">{link.body}</p>
                <span className="mt-5 inline-flex items-center gap-2 text-sm font-semibold text-accent">
                  {link.cta}
                  <ArrowRight size={16} weight="bold" className="transition-transform group-hover:translate-x-1" aria-hidden />
                </span>
              </a>
            ))}
          </div>
        </div>

        <div className={ruleStackClass + " mt-5"}>
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
              className="group grid gap-2 border-b border-white/10 px-5 py-5 last:border-b-0 hover:bg-white/[0.035] md:grid-cols-[0.9fr_1.4fr_auto] md:items-center"
            >
              <span className="text-sm font-semibold text-ivory/50">{link.label}</span>
              <span className="break-all text-sm font-medium text-ivory">{link.value}</span>
              <ArrowRight size={18} weight="bold" className="text-accent transition-transform group-hover:translate-x-1" aria-hidden />
            </a>
          ))}
        </div>
      </SectionShell>
    </section>
  );
}

function SupportPage() {
  const mailto = "mailto:" + site.supportEmail + "?subject=MyLeafy Support";

  return (
    <>
      <PageHero
        icon={Headset}
        label="Support"
        title="Help when campus data gets complicated."
        body="For login, sync, timetable parsing, community, sharing, or ratings, contact support by email or through in-app feedback."
        image="/media/campus/snowy-campus-building.jpg"
        imageAlt="A snow-covered BJFU campus building"
      >
        <div className="mt-8 flex flex-col gap-3 sm:flex-row">
          <TapButton href={mailto} className={primaryButtonClass}>
            <EnvelopeSimple size={18} weight="bold" aria-hidden />
            Send email
          </TapButton>
          <CopyEmailButton email={site.supportEmail} />
        </div>
      </PageHero>

      <SectionShell title="Public contact" body="Email works for general support and privacy requests. In-app feedback is better when an issue needs device and sync context.">
        <div className="grid gap-5 lg:grid-cols-[1.2fr_0.8fr]">
          <div className={panelClass}>
            <p className="text-sm font-semibold text-ivory/50">Support email</p>
            <a className="mt-3 block break-all text-3xl font-semibold leading-tight text-ivory hover:text-accent" href={mailto}>
              {site.supportEmail}
            </a>
            <p className="mt-4 max-w-[68ch] text-sm leading-relaxed text-ivory/60">
              Use this address for App Store support, general feedback, feature requests, and privacy requests.
            </p>
          </div>
          <div id="in-app" className={featuredPanelClass + " scroll-mt-24"}>
            <CheckCircle size={24} weight="bold" className="text-accent" aria-hidden />
            <p className="mt-4 text-xl font-semibold text-ivory">In-app feedback includes useful context</p>
            <p className="mt-3 text-sm leading-relaxed text-ivory/60">
              It can include device model, system version, app version, login state, and latest sync time.
            </p>
          </div>
        </div>
      </SectionShell>

      <SectionShell title="Information to include">
        <NumberedList items={supportChecklist} />
      </SectionShell>

      <SectionShell title="Common support topics">
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
        title="Clear data boundaries, written plainly."
        body={"How MyLeafy handles school login, local cache, community, feedback, ratings, sharing, and website data. Updated " + site.updatedAt + "."}
        image="/media/campus/classroom-at-dusk.jpg"
        imageAlt="A quiet BJFU classroom at dusk"
      >
        <div className="mt-8 flex flex-col gap-3 sm:flex-row">
          <TapButton href="#privacy-rights" className={primaryButtonClass}>
            <LockKey size={18} weight="bold" aria-hidden />
            View privacy choices
          </TapButton>
          <TapButton href={"mailto:" + site.supportEmail + "?subject=MyLeafy Privacy Request"} className={secondaryButtonClass}>
            <EnvelopeSimple size={18} weight="bold" aria-hidden />
            Send privacy request
          </TapButton>
        </div>
      </PageHero>

      <SectionShell title="Four things to know">
        <AsymmetricIconGrid items={privacySummaryCards} />
      </SectionShell>

      <article className="mx-auto max-w-6xl px-4 pb-24 md:px-6 md:pb-32">
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
        title="Open a shared week in MyLeafy."
        body="Copy the invite code, then accept it from Profile, Shared Timetable, and the add button."
        image="/media/campus/spring-blossoms-cat.jpg"
        imageAlt="Spring blossoms and a campus cat at BJFU"
      >
        <div className="mt-8 grid max-w-xl gap-4">
          <div className={featuredPanelClass}>
            <p className="text-sm font-semibold text-ivory/50">Invite code</p>
            <p className="mt-3 break-all text-5xl font-semibold tracking-[-0.03em] text-ivory">{normalizedCode || "Not recognized"}</p>
            <p className="mt-4 text-sm leading-relaxed text-ivory/60">
              Invite codes are valid for seven days and can be accepted by one person. Access can be revoked later.
            </p>
          </div>
          <button type="button" onClick={copyCode} className={primaryButtonClass + " leafy-pressable inline-flex min-h-11 w-fit items-center gap-2 rounded-full px-5 text-sm font-medium"}>
            <CheckCircle size={18} weight="bold" aria-hidden />
            {copied ? "Copied" : "Copy invite code"}
          </button>
        </div>
      </PageHero>

      <SectionShell title="Accept in the app">
        <NumberedList items={["Open MyLeafy.", "Go to Profile -> Shared Timetable.", "Tap + in the top-right corner.", "Paste the invite code and accept it."]} />
      </SectionShell>
    </>
  );
}

function ShareCommunityPostPage({ postID }: { postID: string }) {
  const normalizedPostID = postID.match(/^[0-9a-fA-F-]{36}$/) ? postID : "";
  const appURL = normalizedPostID ? "https://" + site.domain + "/share/community/post/" + normalizedPostID + "?open=1" : site.homeUrl;

  return (
    <>
      <PageHero
        icon={ChatsCircle}
        label="Community post"
        title="Continue the conversation in MyLeafy."
        body="This share link opens the post detail in the latest version of the app."
        image="/media/campus/campus-entrance-bicycles.jpg"
        imageAlt="Bicycles parked at a BJFU campus entrance"
      >
        <div className="mt-8 flex flex-col gap-3 sm:flex-row">
          <TapButton href={appURL} className={primaryButtonClass}>
            <DeviceMobile size={18} weight="bold" aria-hidden />
            Open MyLeafy
          </TapButton>
          <TapButton href={site.appStoreUrl || site.supportUrl} className={secondaryButtonClass}>
            <ArrowRight size={18} weight="bold" aria-hidden />
            Get MyLeafy
          </TapButton>
        </div>
      </PageHero>

      <SectionShell title="Community content opens in the app">
        <NumberedList
          items={[
            "Share cards may show the post title and a short summary. Comments stay in the app.",
            "After signing in to MyLeafy, the app opens the post detail.",
            "If the app opens but does not show the post, update MyLeafy and try again.",
            "If the post has been deleted or is no longer visible, the app will explain that it cannot be opened."
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
  image,
  imageAlt,
  children
}: {
  icon: IconComponent;
  label: string;
  title: string;
  body: string;
  image: string;
  imageAlt: string;
  children?: ReactNode;
}) {
  return (
    <section className="overflow-hidden border-b border-white/[0.07] bg-forest-low px-4 pb-20 pt-32 md:px-6 md:pb-28 md:pt-40">
      <div className="mx-auto grid max-w-7xl gap-12 lg:grid-cols-[0.9fr_1.1fr] lg:items-center">
        <StaggerReveal className="max-w-2xl">
          <span className="grid h-12 w-12 place-items-center rounded-2xl bg-accent-muted text-accent">
            <Icon size={24} weight="regular" aria-hidden />
          </span>
          <p className="mt-7 text-sm font-semibold text-accent">{label}</p>
          <h1 className="mt-5 text-5xl font-semibold leading-[0.96] tracking-[-0.055em] text-ivory md:text-7xl">{title}</h1>
          <p className="mt-6 max-w-xl text-base leading-relaxed text-ivory/60 md:text-lg">{body}</p>
          {children}
        </StaggerReveal>
        <ScrollReveal className="overflow-hidden rounded-[28px] border border-white/10 shadow-deep">
          <img className="aspect-[4/3] w-full object-cover" src={image} alt={imageAlt} decoding="async" />
        </ScrollReveal>
      </div>
    </section>
  );
}

function SectionShell({
  title,
  body,
  children,
  id
}: {
  title: string;
  body?: string;
  children: ReactNode;
  id?: string;
}) {
  return (
    <section id={id} className="mx-auto max-w-7xl scroll-mt-24 px-4 py-20 md:px-6 md:py-28">
      <ScrollReveal className="mb-12 max-w-4xl">
        <h2 className="text-4xl font-semibold leading-[1.02] tracking-[-0.045em] text-ivory md:text-6xl">{title}</h2>
        {body && <p className="mt-5 max-w-2xl text-base leading-relaxed text-ivory/60">{body}</p>}
      </ScrollReveal>
      {children}
    </section>
  );
}

function NumberedList({ items }: { items: string[] }) {
  return (
    <div className={ruleStackClass}>
      {items.map((item, index) => (
        <div key={item} className="grid grid-cols-[48px_1fr] gap-4 border-b border-white/10 px-5 py-5 last:border-b-0">
          <span className="text-sm font-semibold text-accent">{String(index + 1).padStart(2, "0")}</span>
          <p className="text-sm leading-relaxed text-ivory/60">{item}</p>
        </div>
      ))}
    </div>
  );
}

function AsymmetricIconGrid({ items }: { items: Array<{ icon: IconComponent; title: string; body: string }> }) {
  return (
    <div className="grid gap-5 lg:grid-cols-2">
      {items.map((item) => {
        const Icon = item.icon;
        return (
          <article key={item.title} className={panelClass}>
            <span className="grid h-11 w-11 place-items-center rounded-xl bg-accent-muted text-accent">
              <Icon size={23} weight="bold" aria-hidden />
            </span>
            <h3 className="mt-6 text-xl font-semibold text-ivory">{item.title}</h3>
            <p className="mt-3 max-w-[68ch] text-sm leading-relaxed text-ivory/60">{item.body}</p>
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
    <section id={section.id} className="grid scroll-mt-24 gap-7 border-b border-white/10 px-5 py-9 last:border-b-0 md:grid-cols-[0.42fr_1fr] md:px-8">
      <div className="flex items-start gap-3">
        <span className="grid h-10 w-10 shrink-0 place-items-center rounded-xl bg-accent-muted text-accent">
          <Icon size={21} weight="bold" aria-hidden />
        </span>
        <h2 className="text-2xl font-semibold leading-tight text-ivory">{section.title}</h2>
      </div>
      <div className="space-y-4">
        {section.items.map((item) => (
          <p key={item} className="text-sm leading-relaxed text-ivory/60">
            {item}
          </p>
        ))}
      </div>
    </section>
  );
}

function Footer({ navigate }: { navigate: (href: string) => void }) {
  return (
    <footer className="border-t border-white/[0.07] bg-forest-low">
      <div className="mx-auto grid max-w-7xl gap-12 px-4 py-14 md:px-6 lg:grid-cols-[1.05fr_1.95fr]">
        <div>
          <div className="flex items-center gap-3">
            <img className="h-11 w-11 rounded-[13px] border border-white/10 shadow-deep" src="/app-icon.png" alt="MyLeafy app icon" />
            <div>
              <p className="text-xl font-semibold leading-none text-ivory">MyLeafy</p>
              <p className="mt-1 text-sm font-medium text-ivory/50">BJFU campus tool</p>
            </div>
          </div>
          <p className="mt-6 max-w-sm text-sm leading-relaxed text-ivory/50">
            Currently supports Beijing Forestry University.
          </p>
          <a
            href={"mailto:" + site.supportEmail}
            className="leafy-pressable mt-6 inline-flex min-h-11 items-center gap-2 rounded-full border border-white/10 bg-white/[0.04] px-4 text-sm font-semibold text-ivory hover:border-accent/30 hover:text-accent"
          >
            <EnvelopeSimple size={17} weight="bold" aria-hidden />
            {site.supportEmail}
          </a>
        </div>

        <nav className="grid gap-8 sm:grid-cols-2 lg:grid-cols-4">
          {footerGroups.map((group) => (
            <div key={group.title}>
              <h2 className="text-sm font-semibold text-ivory">{group.title}</h2>
              <div className="mt-4 grid gap-3">
                {group.links.map((link) => (
                  <a
                    key={group.title + "-" + link.label}
                    href={link.href}
                    onClick={(event) => {
                      if (link.href.startsWith("http") && !link.href.includes(site.domain)) return;
                      if (link.href.startsWith("mailto:")) return;
                      event.preventDefault();
                      navigate(link.href);
                    }}
                    className="break-words text-sm font-medium leading-relaxed text-ivory/50 hover:text-accent"
                  >
                    {link.label}
                  </a>
                ))}
              </div>
            </div>
          ))}
        </nav>
      </div>
      <div className="border-t border-white/[0.07] px-4 py-5 md:px-6">
        <div className="mx-auto flex max-w-7xl flex-col gap-3 text-xs font-medium text-ivory/40 md:flex-row md:items-center md:justify-between">
          <div className="grid gap-1">
            <span>Last updated: {site.updatedAt}</span>
            <span>Apple, the Apple logo, App Store, and iPhone are trademarks of Apple Inc.</span>
          </div>
          <div className="flex flex-wrap gap-x-5 gap-y-2">
            <a
              className="inline-flex items-center gap-2 hover:text-accent"
              href="/"
              onClick={(event) => {
                event.preventDefault();
                navigate("/");
              }}
            >
              <House size={15} aria-hidden />
              Home
            </a>
            <a className="inline-flex items-center gap-2 hover:text-accent" href={"mailto:" + site.supportEmail}>
              <EnvelopeSimple size={15} aria-hidden />
              Contact
            </a>
          </div>
        </div>
      </div>
    </footer>
  );
}
