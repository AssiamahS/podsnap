// node tests/extract.test.mjs — pulls extract() out of app.js and runs it on sample BOL / rate con text.
import { readFileSync } from "node:fs";
import assert from "node:assert/strict";
const src = readFileSync(new URL("../web/app.js", import.meta.url), "utf8");
const body = src.slice(src.indexOf("function extract("), src.indexOf("// ---------- PDF packet"));
const extract = new Function(body + "; return extract;")();

const bol = `STRAIGHT BILL OF LADING
BOL # 88123456
Date: 10/24/2026
Shipper
Acme Foods Inc
1200 Industrial Pkwy
Elizabeth, NJ 07201
Consignee
Wegmans DC 41
55 Commerce Dr
Pottsville, PA 17901
Carrier: Sly Hauling LLC MC# 123456
PO # 4500998
Received in good order 10/25/2026 signature`;
const ratecon = `RATE CONFIRMATION
Swift Lane Logistics LLC MC 987654
Load # SL-77821
Carrier Pay
Linehaul $2,350.00
Detention $75.00
Send invoices to ap@swiftlane.example`;

const a = extract(bol, { c_name: "Sly Hauling LLC", c_mc: "123456" });
assert.equal(a.bol_no, "88123456");
assert.equal(a.po_no, "4500998");
assert.match(a.shipper, /^Acme Foods Inc\n1200 Industrial Pkwy/);
assert.match(a.consignee, /^Wegmans DC 41/);
assert.equal(a.del_date, "2026-10-25");
assert.equal(a.broker_mc, undefined);

const b = extract(ratecon, { c_mc: "123456" });
assert.equal(b.load_no, "SL-77821");
assert.equal(b.rate, "2350.00");
assert.equal(b.detention, "75.00");
assert.equal(b.broker_email, "ap@swiftlane.example");
assert.equal(b.broker_mc, "987654");
assert.match(b.broker, /Swift Lane Logistics/);
assert.equal(extract("Product description 1234 widgets").load_no, "");
console.log("extract: all assertions passed");
