import type { Config } from "tailwindcss";

const config: Config = {
  content: ["./index.html", "./src/**/*.{ts,tsx}"],
  theme: {
    extend: {
      colors: {
        primary: {
          DEFAULT: "#1F6A45",
          strong: "#155638",
          ink: "#164A32",
          wash: "#EAF5EC",
          soft: "#F5FAF6"
        },
        secondary: {
          DEFAULT: "#D8CC8F",
          ink: "#6D6234",
          wash: "#F4EFCF",
          soft: "#FBF7E5"
        },
        leaf: {
          deep: "#1E4F3E",
          mid: "#4E8261",
          light: "#8DAA6E",
          paper: "#D8CC8F"
        },
        neutral: {
          50: "#F9FAFB",
          100: "#F3F4F6",
          200: "#E5E7EB",
          300: "#D1D5DB",
          500: "#6B7280",
          600: "#4B5563",
          700: "#374151",
          800: "#1F2937",
          900: "#111827"
        },
        success: "#2F8F55",
        warning: "#B7791F",
        danger: "#B42318",
        info: "#4F8F67",
        surface: "#FFFFFF",
        "surface-high": "#F4F8F4",
        "surface-low": "#E7F2E9",
        text: "#102018",
        paper: {
          DEFAULT: "#FFFFFF",
          muted: "#F4F8F4"
        }
      },
      boxShadow: {
        soft: "0 10px 30px rgba(16, 32, 24, 0.07)",
        lift: "0 24px 70px rgba(16, 32, 24, 0.11)",
        primary: "0 18px 46px rgba(31, 106, 69, 0.22)",
        line: "inset 0 0 0 1px rgba(23, 23, 23, 0.08)"
      },
      fontFamily: {
        sans: ["-apple-system", "BlinkMacSystemFont", "SF Pro Text", "Inter", "Helvetica Neue", "Arial", "sans-serif"],
        display: ["-apple-system", "BlinkMacSystemFont", "SF Pro Display", "Inter", "Helvetica Neue", "Arial", "sans-serif"],
        mono: ["SFMono-Regular", "Consolas", "\"Liberation Mono\"", "monospace"]
      }
    }
  },
  plugins: []
};

export default config;
