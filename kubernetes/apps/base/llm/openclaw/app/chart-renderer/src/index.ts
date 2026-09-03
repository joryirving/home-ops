import { Type } from "typebox";
import { defineToolPlugin } from "openclaw/plugin-sdk/tool-plugin";
import { saveMediaBuffer } from "openclaw/plugin-sdk/media-store";

const MAX_POINTS = 500;
const MAX_DIMENSION = 2400;
const DEFAULT_WIDTH = 900;
const DEFAULT_HEIGHT = 520;
const DEFAULT_BACKGROUND = "#f8f4ea";

const parameters = Type.Object({
  title: Type.String({ minLength: 1, maxLength: 160 }),
  subtitle: Type.Optional(Type.String({ maxLength: 240 })),
  chartType: Type.Union([
    Type.Literal("line"),
    Type.Literal("bar"),
    Type.Literal("scatter"),
    Type.Literal("area"),
  ]),
  xLabel: Type.Optional(Type.String({ maxLength: 80 })),
  yLabel: Type.Optional(Type.String({ maxLength: 80 })),
  width: Type.Optional(Type.Integer({ minimum: 320, maximum: MAX_DIMENSION })),
  height: Type.Optional(Type.Integer({ minimum: 240, maximum: MAX_DIMENSION })),
  background: Type.Optional(Type.String({ maxLength: 32 })),
  points: Type.Array(
    Type.Object({
      x: Type.Union([Type.String({ maxLength: 120 }), Type.Number()]),
      y: Type.Number(),
      series: Type.Optional(Type.String({ maxLength: 80 })),
    }),
    { minItems: 1, maxItems: MAX_POINTS },
  ),
});

type ChartPoint = {
  x: string | number;
  y: number;
  series?: string;
};

function buildSpec(input: {
  title: string;
  subtitle?: string;
  chartType: "line" | "bar" | "scatter" | "area";
  xLabel?: string;
  yLabel?: string;
  width?: number;
  height?: number;
  background?: string;
  points: ChartPoint[];
}) {
  const xIsNumeric = input.points.every((point) => typeof point.x === "number");
  const hasSeries = input.points.some((point) => point.series);
  const mark = input.chartType === "scatter"
    ? { type: "point", filled: true, size: 90 }
    : input.chartType === "bar"
      ? { type: "bar", cornerRadiusEnd: 3 }
      : { type: input.chartType, point: input.chartType === "line" };

  return {
    $schema: "https://vega.github.io/schema/vega-lite/v6.json",
    title: {
      text: input.title,
      ...(input.subtitle ? { subtitle: input.subtitle } : {}),
      anchor: "start",
      fontSize: 22,
      subtitleFontSize: 13,
      color: "#14201b",
    },
    width: input.width ?? DEFAULT_WIDTH,
    height: input.height ?? DEFAULT_HEIGHT,
    background: input.background ?? DEFAULT_BACKGROUND,
    data: { values: input.points },
    mark,
    encoding: {
      x: {
        field: "x",
        type: xIsNumeric ? "quantitative" : "ordinal",
        title: input.xLabel ?? null,
        sort: xIsNumeric ? undefined : null,
        axis: { labelAngle: xIsNumeric ? 0 : -25, labelLimit: 180 },
      },
      y: {
        field: "y",
        type: "quantitative",
        title: input.yLabel ?? null,
        scale: { zero: input.chartType === "bar" || input.chartType === "area" },
      },
      ...(hasSeries
        ? {
            color: {
              field: "series",
              type: "nominal",
              title: null,
              scale: { scheme: "tableau10" },
            },
          }
        : { color: { value: "#176b55" } }),
      tooltip: [
        { field: "x", type: xIsNumeric ? "quantitative" : "ordinal" },
        { field: "y", type: "quantitative" },
        ...(hasSeries ? [{ field: "series", type: "nominal" }] : []),
      ],
    },
    config: {
      font: "sans-serif",
      view: { stroke: null },
      axis: {
        domainColor: "#78877f",
        gridColor: "#d7ded9",
        labelColor: "#28342f",
        titleColor: "#28342f",
      },
      legend: { labelColor: "#28342f" },
    },
  };
}

export default defineToolPlugin({
  id: "chart-renderer",
  name: "Chart Renderer",
  description: "Render deterministic data charts as PNG attachments.",
  tools: (tool) => [
    tool({
      name: "chart_generate",
      description:
        "Render a deterministic line, bar, scatter, or area chart from structured numeric data and attach the PNG to the current reply.",
      parameters,
      factory({ toolContext }) {
        if (toolContext.sandboxed) {
          return null;
        }
        return {
          name: "chart_generate",
          label: "Chart Generator",
          description:
            "Render a deterministic line, bar, scatter, or area chart from structured numeric data and attach the PNG to the current reply.",
          parameters,
          execute: async (_toolCallId, rawInput) => {
            const input = rawInput as {
              title: string;
              subtitle?: string;
              chartType: "line" | "bar" | "scatter" | "area";
              xLabel?: string;
              yLabel?: string;
              width?: number;
              height?: number;
              background?: string;
              points: ChartPoint[];
            };
            if (!input.points.every((point) => Number.isFinite(point.y))) {
              throw new Error("All y values must be finite numbers.");
            }

            const [{ compile }, { parse, View }, { Resvg }] = await Promise.all([
              import("vega-lite"),
              import("vega"),
              import("@resvg/resvg-js"),
            ]);
            const spec = buildSpec(input);
            const runtime = parse(compile(spec as never).spec);
            const view = new View(runtime, { renderer: "none" });
            const svg = await view.toSVG();
            view.finalize();

            const png = new Resvg(svg, {
              fitTo: { mode: "original" },
              background: input.background ?? DEFAULT_BACKGROUND,
            }).render().asPng();
            const slug = input.title
              .toLowerCase()
              .replace(/[^a-z0-9]+/g, "-")
              .replace(/^-|-$/g, "")
              .slice(0, 64);
            const saved = await saveMediaBuffer(
              Buffer.from(png),
              "image/png",
              "outbound",
              5_000_000,
              `${slug || "chart"}.png`,
            );

            return {
              content: [
                {
                  type: "text",
                  text: `Rendered ${input.chartType} chart with ${input.points.length} points.`,
                },
              ],
              details: {
                media: {
                  mediaUrl: saved.path,
                  outbound: true,
                },
              },
            };
          },
        };
      },
    }),
  ],
});
