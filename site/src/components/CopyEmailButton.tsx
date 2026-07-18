import { useEffect, useState } from "react";
import { CheckCircle, Copy, WarningCircle } from "@phosphor-icons/react";
import { TapButton } from "./MotionBits";

type CopyState = "idle" | "copying" | "copied" | "error";

export function CopyEmailButton({ email }: { email: string }) {
  const [state, setState] = useState<CopyState>("idle");

  useEffect(() => {
    if (state !== "copied" && state !== "error") {
      return undefined;
    }

    const timeout = window.setTimeout(() => setState("idle"), 2200);
    return () => window.clearTimeout(timeout);
  }, [state]);

  async function copyEmail() {
    setState("copying");
    try {
      await navigator.clipboard.writeText(email);
      setState("copied");
    } catch {
      setState("error");
    }
  }

  const Icon = state === "copied" ? CheckCircle : state === "error" ? WarningCircle : Copy;
  const label = state === "copying" ? "Copying" : state === "copied" ? "Copied" : state === "error" ? "Copy failed" : "Copy email";
  const toneClass =
    state === "copied"
      ? "border border-success bg-success text-white hover:bg-success"
      : state === "error"
        ? "border border-danger bg-danger text-white hover:bg-danger"
        : state === "copying"
          ? "border border-warning/40 bg-warning/10 text-ivory"
          : "border border-white/20 bg-forest-elevated/80 text-ivory shadow-deep hover:border-white/30 hover:bg-forest-elevated";

  return (
    <TapButton
      onClick={copyEmail}
      disabled={state === "copying"}
      className={toneClass}
    >
      <Icon size={18} weight="bold" aria-hidden />
      {label}
    </TapButton>
  );
}
