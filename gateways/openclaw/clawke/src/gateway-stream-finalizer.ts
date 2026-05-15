export class GatewayBoundaryFinalizer {
  private readonly boundaryFinalizedTexts = new Set<string>();

  recordBoundaryFinalized(text: string): void {
    const key = normalizeText(text);
    if (key) {
      this.boundaryFinalizedTexts.add(key);
    }
  }

  consumeDuplicateFinal(text: string): boolean {
    const key = normalizeText(text);
    if (!key || !this.boundaryFinalizedTexts.has(key)) {
      return false;
    }
    this.boundaryFinalizedTexts.delete(key);
    return true;
  }
}

function normalizeText(text: string): string {
  return text.replace(/\s+/g, " ").trim();
}

export type GatewayFinalDeliverySkipReason = "duplicate_text" | "boundary_duplicate";

export class GatewayFinalDeliveryGuard {
  private readonly deliveredTexts = new Set<string>();
  private readonly boundaryFinalizer: GatewayBoundaryFinalizer;

  constructor(boundaryFinalizer = new GatewayBoundaryFinalizer()) {
    this.boundaryFinalizer = boundaryFinalizer;
  }

  recordBoundaryFinalized(text: string): void {
    this.boundaryFinalizer.recordBoundaryFinalized(text);
  }

  check(kind: string, text: string): { skip: false } | { skip: true; reason: GatewayFinalDeliverySkipReason } {
    const dedupeKey = `${kind}:${text.slice(0, 200)}`;
    if (this.deliveredTexts.has(dedupeKey)) {
      return { skip: true, reason: "duplicate_text" };
    }

    if (kind === "final" && this.boundaryFinalizer.consumeDuplicateFinal(text)) {
      this.deliveredTexts.add(dedupeKey);
      return { skip: true, reason: "boundary_duplicate" };
    }

    this.deliveredTexts.add(dedupeKey);
    return { skip: false };
  }
}
