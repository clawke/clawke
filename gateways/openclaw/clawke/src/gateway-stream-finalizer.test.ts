import test from "node:test";
import assert from "node:assert/strict";
import {
  GatewayBoundaryFinalizer,
  GatewayFinalDeliveryGuard,
} from "./gateway-stream-finalizer.ts";

test("GatewayBoundaryFinalizer consumes duplicate final text after boundary finalization", () => {
  const finalizer = new GatewayBoundaryFinalizer();

  finalizer.recordBoundaryFinalized("好问题，让我查一下 skill 的状态:");

  assert.equal(
    finalizer.consumeDuplicateFinal("好问题，让我查一下 skill 的状态:"),
    true,
  );
  assert.equal(
    finalizer.consumeDuplicateFinal("好问题，让我查一下 skill 的状态:"),
    false,
  );
});

test("GatewayBoundaryFinalizer does not suppress different final text", () => {
  const finalizer = new GatewayBoundaryFinalizer();

  finalizer.recordBoundaryFinalized("先查一下状态");

  assert.equal(finalizer.consumeDuplicateFinal("状态正常"), false);
});

test("GatewayFinalDeliveryGuard skips boundary duplicate before regular final delivery", () => {
  const guard = new GatewayFinalDeliveryGuard();

  guard.recordBoundaryFinalized("好嘞！小丽收到，华哥 🫡\n\n让我把这些记下来。");

  assert.deepEqual(
    guard.check("final", "好嘞！小丽收到，华哥 🫡 让我把这些记下来。"),
    { skip: true, reason: "boundary_duplicate" },
  );
  assert.deepEqual(
    guard.check("final", "记住了！我是小丽，华哥在杭州的AI小伙伴。"),
    { skip: false },
  );
});

test("GatewayFinalDeliveryGuard keeps skipped boundary duplicate idempotent", () => {
  const guard = new GatewayFinalDeliveryGuard();

  guard.recordBoundaryFinalized("已处理第一段");

  assert.deepEqual(guard.check("final", "已处理第一段"), {
    skip: true,
    reason: "boundary_duplicate",
  });
  assert.deepEqual(guard.check("final", "已处理第一段"), {
    skip: true,
    reason: "duplicate_text",
  });
});
