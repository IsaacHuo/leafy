import React, { PropsWithChildren } from "react";
import { motion, useReducedMotion } from "framer-motion";

const easeOut = [0.23, 1, 0.32, 1] as const;

export function StaggerReveal({ children, className }: PropsWithChildren<{ className?: string }>) {
  const shouldReduceMotion = useReducedMotion();

  if (shouldReduceMotion) {
    return <div className={className}>{children}</div>;
  }

  return (
    <motion.div
      className={className}
      initial="hidden"
      animate="visible"
      variants={{
        hidden: {},
        visible: {
          transition: {
            staggerChildren: 0.055
          }
        }
      }}
    >
      {React.Children.map(children, (child) => (
        <motion.div
          variants={{
            hidden: { opacity: 0, transform: "translate3d(0, 12px, 0)" },
            visible: {
              opacity: 1,
              transform: "translate3d(0, 0, 0)",
              transition: { duration: 0.52, ease: easeOut }
            }
          }}
        >
          {child}
        </motion.div>
      ))}
    </motion.div>
  );
}

export function ScrollReveal({ children, className }: PropsWithChildren<{ className?: string }>) {
  const shouldReduceMotion = useReducedMotion();

  return (
    <motion.div
      className={className}
      initial={shouldReduceMotion ? undefined : { opacity: 0, transform: "translate3d(0, 8px, 0)" }}
      animate={{ opacity: 1, transform: "translate3d(0, 0, 0)" }}
      transition={{ duration: shouldReduceMotion ? 0.2 : 0.46, ease: easeOut }}
    >
      {children}
    </motion.div>
  );
}

export const FloatingStatus = React.memo(function FloatingStatus() {
  const shouldReduceMotion = useReducedMotion();

  return (
    <motion.div
      className="pointer-events-none absolute right-4 top-4 hidden rounded-md border border-black/10 bg-white/90 px-3 py-2 text-xs font-medium text-text shadow-soft backdrop-blur md:block"
      animate={shouldReduceMotion ? undefined : { y: [0, -5, 0], opacity: [0.92, 1, 0.92] }}
      transition={
        shouldReduceMotion
          ? undefined
          : {
              duration: 4.8,
              repeat: Infinity,
              type: "spring",
              stiffness: 100,
              damping: 20
            }
      }
    >
      <span className="mr-2 inline-block h-2 w-2 rounded-full bg-primary align-middle shadow-[0_0_0_4px_rgba(79,143,103,0.16)]" />
      Today's timetable cached
    </motion.div>
  );
});

export const MetricRail = React.memo(function MetricRail() {
  const shouldReduceMotion = useReducedMotion();
  const metrics = [
    ["Timetable", "Current week"],
    ["Grades", "Academic sync"],
    ["Community", "Anonymous session"],
    ["Ratings", "Star summaries"],
    ["Feedback", "In-app submit"]
  ];

  return (
    <div className="overflow-hidden border-y border-black/10 bg-white py-3">
      <motion.div
        className="mx-auto flex max-w-7xl flex-wrap gap-3 px-4 md:px-6"
        initial={shouldReduceMotion ? undefined : { opacity: 0 }}
        animate={shouldReduceMotion ? undefined : { opacity: 1 }}
        transition={shouldReduceMotion ? undefined : { duration: 0.8, ease: [0.16, 1, 0.3, 1] }}
      >
        {metrics.map(([label, value]) => (
          <div
            key={label}
            className="flex min-w-40 items-center justify-between gap-7 rounded-md border border-black/10 bg-paper px-4 py-3"
          >
            <span className="text-sm font-medium text-text/60">{label}</span>
            <span className="text-sm font-medium text-text">{value}</span>
          </div>
        ))}
      </motion.div>
    </div>
  );
});

export function TapButton({
  children,
  className,
  href,
  onClick,
  disabled = false
}: PropsWithChildren<{
  className?: string;
  href?: string;
  onClick?: () => void;
  disabled?: boolean;
}>) {
  const shouldReduceMotion = useReducedMotion();
  const classes = `leafy-pressable inline-flex min-h-11 items-center justify-center gap-2 rounded-xl px-4 text-center text-sm font-medium transition-[background-color,border-color,color,box-shadow] duration-200 disabled:cursor-progress disabled:opacity-70 ${className ?? ""}`;

  if (href) {
    return (
      <motion.a
        href={href}
        className={classes}
        whileHover={shouldReduceMotion ? undefined : { transform: "translate3d(0, -1px, 0)" }}
        whileTap={shouldReduceMotion ? undefined : { transform: "translate3d(0, 0, 0) scale(0.97)" }}
        transition={{ duration: 0.16, ease: easeOut }}
      >
        {children}
      </motion.a>
    );
  }

  return (
    <motion.button
      type="button"
      onClick={onClick}
      disabled={disabled}
      className={classes}
      whileHover={shouldReduceMotion ? undefined : { transform: "translate3d(0, -1px, 0)" }}
      whileTap={shouldReduceMotion ? undefined : { transform: "translate3d(0, 0, 0) scale(0.97)" }}
      transition={{ duration: 0.16, ease: easeOut }}
    >
      {children}
    </motion.button>
  );
}
