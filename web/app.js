/* PODsnap web — BOL/POD photo -> on-device OCR -> invoice + factoring packet PDF.
   No backend. Form data in localStorage, page images in IndexedDB (falls back to memory). */
(() => {
  "use strict";

  const CFG = window.PODSNAP_CONFIG || {};
  const LIBS = {
    ocr: "https://cdn.jsdelivr.net/npm/tesseract.js@5.1.1/dist/tesseract.min.js",
    pdf: "https://cdnjs.cloudflare.com/ajax/libs/jspdf/2.5.1/jspdf.umd.min.js"
  };
  const K = { carrier: "podsnap.carrier", loads: "podsnap.loads", current: "podsnap.current", pane: "podsnap.pane" };
  const $ = (s, r = document) => r.querySelector(s);
  const $$ = (s, r = document) => [...r.querySelectorAll(s)];

  // ---------- storage ----------
  const ls = {
    get(k, d) { try { const v = localStorage.getItem(k); return v ? JSON.parse(v) : d; } catch { return d; } },
    set(k, v) { try { localStorage.setItem(k, JSON.stringify(v)); return true; } catch { return false; } }
  };

  const memImgs = new Map();
  let dbp = null;
  function db() {
    if (!("indexedDB" in window)) return Promise.resolve(null);
    if (!dbp) dbp = new Promise((res) => {
      try {
        const rq = indexedDB.open("podsnap", 1);
        rq.onupgradeneeded = () => rq.result.createObjectStore("imgs");
        rq.onsuccess = () => res(rq.result);
        rq.onerror = () => res(null);
      } catch { res(null); }
    });
    return dbp;
  }
  async function idb(mode, fn) {
    const d = await db();
    if (!d) return null;
    return new Promise((res) => {
      try {
        const tx = d.transaction("imgs", mode);
        const rq = fn(tx.objectStore("imgs"));
        tx.oncomplete = () => res(rq && rq.result);
        tx.onerror = () => res(null);
      } catch { res(null); }
    });
  }
  const imgPut = async (id, url) => { memImgs.set(id, url); await idb("readwrite", (s) => s.put(url, id)); };
  const imgGet = async (id) => memImgs.get(id) || (await idb("readonly", (s) => s.get(id))) || null;
  const imgDel = async (id) => { memImgs.delete(id); await idb("readwrite", (s) => s.delete(id)); };

  // ---------- state ----------
  let carrier = ls.get(K.carrier, { c_next: "1001" });
  let loads = ls.get(K.loads, {});
  let currentId = ls.get(K.current, null);
  let lastField = null;
  let ocrLines = [];

  const uid = () => Date.now().toString(36) + Math.random().toString(36).slice(2, 7);
  const today = () => new Date().toISOString().slice(0, 10);

  function newLoad() {
    const n = parseInt(carrier.c_next, 10) || 1001;
    const id = uid();
    loads[id] = { id, invNo: String(n), created: today(), f: { del_date: today() }, chk: {}, imgs: [] };
    carrier.c_next = String(n + 1);
    ls.set(K.carrier, carrier);
    currentId = id;
    persist();
    return loads[id];
  }
  const cur = () => loads[currentId] || newLoad();

  function persist() {
    const l = loads[currentId];
    if (l) l.updated = Date.now();
    const ok = ls.set(K.loads, loads) && ls.set(K.current, currentId);
    $("#savedHint").textContent = ok ? "Saved on this device" : "Storage full or blocked — export your packet";
  }

  // ---------- form binding ----------
  const form = $("#invForm");
  const fieldEls = () => $$("input, textarea", form);

  function paintForm() {
    const l = cur();
    for (const el of fieldEls()) {
      const src = el.hasAttribute("data-carrier") ? carrier : l.f;
      el.value = src[el.name] ?? "";
    }
    $("#invNoLabel").textContent = "#" + l.invNo;
    $$("[data-chk]").forEach((c) => (c.checked = !!l.chk[c.dataset.chk]));
    paintTotal();
    paintPicker();
    paintThumbs();
    ocrLines = [];
    paintLines();
  }

  form.addEventListener("input", (e) => {
    const el = e.target;
    if (!el.name) return;
    if (el.hasAttribute("data-carrier")) { carrier[el.name] = el.value; ls.set(K.carrier, carrier); }
    else { cur().f[el.name] = el.value; persist(); }
    if (["rate", "detention", "lumper", "other"].includes(el.name)) paintTotal();
    if (["load_no", "del_date"].includes(el.name)) paintPicker();
  });
  form.addEventListener("focusin", (e) => { if (e.target.name) lastField = e.target; });

  $$("[data-chk]").forEach((c) => c.addEventListener("change", () => { cur().chk[c.dataset.chk] = c.checked; persist(); }));

  const num = (v) => { const n = parseFloat(String(v || "").replace(/[^0-9.\-]/g, "")); return isFinite(n) ? n : 0; };
  const usd = (n) => n.toLocaleString("en-US", { style: "currency", currency: "USD" });
  const totalOf = (f) => num(f.rate) + num(f.detention) + num(f.lumper) + num(f.other);
  function paintTotal() { $("#total").textContent = usd(totalOf(cur().f)); }

  function paintPicker() {
    const sel = $("#loadPicker");
    const list = Object.values(loads).sort((a, b) => (b.updated || 0) - (a.updated || 0));
    sel.innerHTML = "";
    for (const l of list) {
      const o = document.createElement("option");
      o.value = l.id;
      o.textContent = `#${l.invNo} · ${l.f.load_no || "no load #"}`;
      if (l.id === currentId) o.selected = true;
      sel.appendChild(o);
    }
  }
  $("#loadPicker").addEventListener("change", (e) => { currentId = e.target.value; persist(); paintForm(); });
  $("#newLoad").addEventListener("click", () => { newLoad(); paintForm(); setPane("docs"); });
  $("#carrierToggle").addEventListener("click", () => {
    const box = $("#carrierBox"); box.hidden = !box.hidden;
    $("#carrierToggle").textContent = box.hidden ? "Your company ▾" : "Your company ▴";
  });

  // ---------- panes (phone / outer display) ----------
  function setPane(p) {
    $("#split").dataset.active = p;
    $$(".tabs button").forEach((b) => b.setAttribute("aria-selected", String(b.dataset.pane === p)));
    ls.set(K.pane, p);
  }
  $$(".tabs button").forEach((b) => b.addEventListener("click", () => setPane(b.dataset.pane)));

  // ---------- images ----------
  function readFile(file) {
    return new Promise((res, rej) => { const r = new FileReader(); r.onload = () => res(r.result); r.onerror = rej; r.readAsDataURL(file); });
  }
  function loadImg(src) {
    return new Promise((res, rej) => { const i = new Image(); i.onload = () => res(i); i.onerror = rej; i.src = src; });
  }
  // Downscale + "scan" look: grayscale with a contrast stretch. Smaller files, better OCR.
  async function scanify(file) {
    const img = await loadImg(await readFile(file));
    const max = 1700;
    const s = Math.min(1, max / Math.max(img.naturalWidth, img.naturalHeight));
    const w = Math.round(img.naturalWidth * s), h = Math.round(img.naturalHeight * s);
    const c = document.createElement("canvas"); c.width = w; c.height = h;
    const x = c.getContext("2d", { willReadFrequently: true });
    x.drawImage(img, 0, 0, w, h);
    const d = x.getImageData(0, 0, w, h), p = d.data;
    const hist = new Uint32Array(256);
    for (let i = 0; i < p.length; i += 4) { const g = (p[i] * 0.299 + p[i + 1] * 0.587 + p[i + 2] * 0.114) | 0; p[i] = g; hist[g]++; }
    const total = w * h; let lo = 0, hi = 255, acc = 0;
    for (; lo < 255; lo++) { acc += hist[lo]; if (acc > total * 0.02) break; }
    acc = 0; for (; hi > 0; hi--) { acc += hist[hi]; if (acc > total * 0.08) break; }
    const span = Math.max(1, hi - lo);
    for (let i = 0; i < p.length; i += 4) { let g = ((p[i] - lo) * 255) / span; g = g < 0 ? 0 : g > 255 ? 255 : g; p[i] = p[i + 1] = p[i + 2] = g; }
    x.putImageData(d, 0, 0);
    return c.toDataURL("image/jpeg", 0.72);
  }

  async function addFiles(files) {
    const l = cur();
    const st = $("#ocrStatus");
    for (const f of files) {
      if (!f.type.startsWith("image/")) continue;
      st.textContent = "Cleaning up page…";
      try {
        const url = await scanify(f);
        const id = uid();
        await imgPut(id, url);
        l.imgs.push({ id, kind: guessKind(l.imgs.length) });
      } catch { st.textContent = "Couldn't read that image"; }
    }
    persist();
    st.textContent = "";
    paintThumbs();
  }
  const guessKind = (i) => ["BOL", "POD", "RATE CON", "LUMPER"][i] || "PAGE";

  async function paintThumbs() {
    const l = cur(), ul = $("#thumbs");
    ul.innerHTML = "";
    for (const im of l.imgs) {
      const li = document.createElement("li");
      const src = await imgGet(im.id);
      li.innerHTML = `<img alt="${im.kind} page"><span class="tag"></span><button class="x" type="button" aria-label="Remove page">×</button>`;
      if (src) li.querySelector("img").src = src;
      const tag = li.querySelector(".tag");
      tag.textContent = im.kind;
      tag.title = "Tap to change label";
      tag.style.cursor = "pointer";
      tag.addEventListener("click", () => {
        const kinds = ["BOL", "POD", "RATE CON", "LUMPER", "PAGE"];
        im.kind = kinds[(kinds.indexOf(im.kind) + 1) % kinds.length];
        tag.textContent = im.kind; persist();
      });
      li.querySelector(".x").addEventListener("click", async () => {
        l.imgs = l.imgs.filter((x) => x.id !== im.id); await imgDel(im.id); persist(); paintThumbs();
      });
      ul.appendChild(li);
    }
    $("#ocrBtn").disabled = l.imgs.length === 0;
  }

  const fileIn = $("#fileIn");
  fileIn.addEventListener("change", () => { addFiles([...fileIn.files]); fileIn.value = ""; });
  const dz = $(".dropzone");
  ["dragenter", "dragover"].forEach((t) => dz.addEventListener(t, (e) => { e.preventDefault(); dz.classList.add("over"); }));
  ["dragleave", "drop"].forEach((t) => dz.addEventListener(t, (e) => { e.preventDefault(); dz.classList.remove("over"); }));
  dz.addEventListener("drop", (e) => addFiles([...(e.dataTransfer?.files || [])]));
  window.addEventListener("paste", (e) => {
    const fs = [...(e.clipboardData?.files || [])];
    if (fs.length) addFiles(fs);
  });

  // ---------- OCR ----------
  const loaded = {};
  function loadScript(src) {
    if (!loaded[src]) loaded[src] = new Promise((res, rej) => {
      const s = document.createElement("script"); s.src = src; s.async = true; s.onload = res; s.onerror = () => { delete loaded[src]; rej(new Error("offline")); };
      document.head.appendChild(s);
    });
    return loaded[src];
  }

  $("#ocrBtn").addEventListener("click", async () => {
    const l = cur(), st = $("#ocrStatus"), btn = $("#ocrBtn");
    btn.disabled = true; st.className = "status";
    try {
      st.textContent = "Loading reader (first time ~10 MB, then cached)…";
      await loadScript(LIBS.ocr);
      const worker = await window.Tesseract.createWorker("eng", 1, {
        logger: (m) => { if (m.status === "recognizing text") st.textContent = `Reading… ${Math.round(m.progress * 100)}%`; }
      });
      let text = "";
      for (const [i, im] of l.imgs.entries()) {
        st.textContent = `Reading page ${i + 1} of ${l.imgs.length}…`;
        const src = await imgGet(im.id);
        if (!src) continue;
        const r = await worker.recognize(src);
        text += "\n" + r.data.text;
      }
      await worker.terminate();
      const got = extract(text, carrier);
      const filled = applyFields(got);
      ocrLines = text.split("\n").map((s) => s.trim()).filter((s) => s.length > 2);
      paintLines();
      $("#ocrBox").open = true;
      st.className = "status ok";
      st.textContent = filled ? `Filled ${filled} field${filled > 1 ? "s" : ""}. Check them.` : "Read the text — tap lines to fill fields.";
      if (filled && matchMedia("(max-width: 699px)").matches) setTimeout(() => setPane("invoice"), 900);
    } catch (e) {
      st.textContent = e.message === "offline" ? "Reader needs a connection the first time." : "Reading failed — fill by hand or retake the photo.";
    } finally { btn.disabled = l.imgs.length === 0; }
  });

  function applyFields(got) {
    const l = cur(); let n = 0;
    for (const [k, v] of Object.entries(got)) {
      if (!v || (l.f[k] && String(l.f[k]).trim())) continue; // never overwrite what the driver typed
      l.f[k] = v; n++;
      const el = form.elements[k];
      if (el) { el.value = v; el.classList.remove("filled"); void el.offsetWidth; el.classList.add("filled"); }
    }
    persist(); paintTotal(); paintPicker();
    return n;
  }

  function paintLines() {
    const ol = $("#ocrLines"); ol.innerHTML = "";
    $("#ocrBox").style.display = ocrLines.length ? "" : "none";
    for (const line of ocrLines.slice(0, 300)) {
      const li = document.createElement("li"), b = document.createElement("button");
      b.type = "button"; b.textContent = line;
      b.addEventListener("click", () => {
        const el = lastField || form.elements.notes;
        el.value = el.tagName === "TEXTAREA" && el.value ? el.value + "\n" + line : line;
        el.dispatchEvent(new Event("input", { bubbles: true }));
        el.classList.remove("filled"); void el.offsetWidth; el.classList.add("filled");
      });
      li.appendChild(b); ol.appendChild(li);
    }
  }

  // ---------- field extraction (exported for tests) ----------
  function extract(text, me = {}) {
    const t = String(text || "").replace(/[|]/g, " ").replace(/[ \t]+/g, " ");
    const lines = t.split(/\r?\n/).map((s) => s.trim()).filter(Boolean);
    const out = {};
    const ID = "((?=[A-Z\\-]*\\d)[A-Z0-9][A-Z0-9\\-]{3,})";
    const SEP = "\\s*(?:#|no\\.?|num(?:ber)?)?\\s*[:#\\-]?\\s*";
    const grab = (re) => { const m = t.match(re); return m ? m[1].trim() : ""; };
    out.load_no = grab(new RegExp("\\b(?:load|pro|order|trip|confirmation)" + SEP + ID, "i"));
    out.bol_no = grab(new RegExp("\\b(?:b\\s*\\/?\\s*o\\s*\\/?\\s*l|bill\\s+of\\s+lading)" + SEP + ID, "i"));
    out.po_no = grab(new RegExp("\\bp\\.?\\s?o\\.?\\s*(?:#|no\\.?|num(?:ber)?)\\s*[:#\\-]?\\s*((?=[A-Z\\-]*\\d)[A-Z0-9][A-Z0-9\\-]{2,})", "i"));

    const money = (s) => [...s.matchAll(/\$\s?(\d{1,3}(?:,\d{3})+(?:\.\d{2})?|\d+(?:\.\d{2})?)/g)].map((m) => parseFloat(m[1].replace(/,/g, "")));
    let rate = 0;
    lines.forEach((ln, i) => {
      if (/(line\s?haul|total|rate|agreed|carrier pay|amount|flat)/i.test(ln) && !/(detention|lumper|fuel tax)/i.test(ln)) {
        const v = money(ln + " " + (lines[i + 1] || ""));
        if (v.length) rate = Math.max(rate, ...v);
      }
    });
    if (!rate) { const all = money(t).filter((v) => v >= 100); if (all.length) rate = Math.max(...all); }
    if (rate) out.rate = rate.toFixed(2);
    lines.forEach((ln) => {
      if (/detention/i.test(ln) && !out.detention) { const v = money(ln); if (v.length) out.detention = v[0].toFixed(2); }
      if (/lumper/i.test(ln) && !out.lumper) { const v = money(ln); if (v.length) out.lumper = v[0].toFixed(2); }
    });

    const STOP = /^(shipper|ship\s*from|origin|pick\s*up|consignee|ship\s*to|receiver|destination|deliver(y)?\s*(to|location)?|carrier|bill\s*to|broker|third\s*party|special|instructions|commodity|weight|pieces|signature|date)\b/i;
    const block = (re) => {
      for (let i = 0; i < lines.length; i++) {
        const m = lines[i].match(re);
        if (!m) continue;
        const rest = lines[i].slice(m.index + m[0].length).replace(/^[\s:#\-]+/, "");
        const got = rest ? [rest] : [];
        for (let j = i + 1; j < lines.length && got.length < 3; j++) {
          if (STOP.test(lines[j])) break;
          got.push(lines[j]);
        }
        if (got.length) return got.join("\n");
      }
      return "";
    };
    out.shipper = block(/\b(shipper|ship\s*from|pick\s*up\s*(location)?|origin)\b\s*(name|info(rmation)?)?/i);
    out.consignee = block(/\b(consignee|ship\s*to|receiver|destination|deliver\s*to)\b\s*(name|info(rmation)?)?/i);
    const billTo = block(/\b(bill\s*to|broker|freight\s*charges\s*bill\s*to)\b\s*(name)?/i);
    if (billTo) out.broker = billTo.split("\n")[0];
    if (!out.broker) {
      const b = lines.find((ln) => /(logistics|brokerage|freight|transportation)\b.*\b(llc|inc|co|corp)?/i.test(ln) && (!me.c_name || !ln.toLowerCase().includes(me.c_name.toLowerCase())));
      if (b) out.broker = b;
    }
    const emails = (t.match(/[\w.+\-]+@[\w\-]+\.[\w.\-]+/g) || []).filter((e) => !me.c_email || e.toLowerCase() !== me.c_email.toLowerCase());
    if (emails.length) out.broker_email = emails.find((e) => /(ap|billing|invoice|accounting|pay)/i.test(e)) || emails[0];
    const mcs = [...t.matchAll(/\bMC\s*#?\s*:?\s*(\d{5,8})/gi)].map((m) => m[1]).filter((m) => m !== String(me.c_mc || "").replace(/\D/g, ""));
    if (mcs.length) out.broker_mc = mcs[0];

    const dateRe = /\b(\d{1,2})[\/\-.](\d{1,2})[\/\-.](\d{2,4})\b/;
    const dl = lines.find((ln) => /deliver|received|arriv/i.test(ln) && dateRe.test(ln)) || lines.find((ln) => dateRe.test(ln));
    if (dl) {
      const [, mo, da, yr] = dl.match(dateRe);
      const y = yr.length === 2 ? "20" + yr : yr;
      if (+mo >= 1 && +mo <= 12 && +da >= 1 && +da <= 31) out.del_date = `${y}-${mo.padStart(2, "0")}-${da.padStart(2, "0")}`;
    }
    return out;
  }

  // ---------- PDF packet ----------
  let lastPacket = null;

  async function buildPacket() {
    await loadScript(LIBS.pdf);
    const { jsPDF } = window.jspdf;
    const l = cur(), f = l.f, c = carrier;
    const doc = new jsPDF({ unit: "pt", format: "letter" });
    const W = 612, M = 48;
    let y = M;
    const ink = () => doc.setTextColor(20, 20, 20);
    const soft = () => doc.setTextColor(95, 95, 95);

    doc.setFillColor(255, 90, 31); doc.rect(0, 0, W, 8, "F");
    doc.setFont("helvetica", "bold"); doc.setFontSize(20); ink();
    doc.text(c.c_name || "Your Carrier LLC", M, y + 14);
    doc.setFontSize(28); doc.text("INVOICE", W - M, y + 16, { align: "right" });
    doc.setFont("helvetica", "normal"); doc.setFontSize(10); soft();
    const cl = [c.c_addr, [c.c_mc && "MC/DOT " + c.c_mc, c.c_phone].filter(Boolean).join("  ·  "), c.c_email].filter(Boolean);
    cl.forEach((s, i) => doc.text(String(s), M, y + 32 + i * 13));
    doc.setFontSize(11); ink();
    doc.text(`No. ${l.invNo}`, W - M, y + 36, { align: "right" });
    doc.text(`Date ${today()}`, W - M, y + 50, { align: "right" });
    doc.text("Terms: Net 30", W - M, y + 64, { align: "right" });
    y += 96;

    doc.setDrawColor(20); doc.setLineWidth(1.2); doc.line(M, y, W - M, y); y += 18;
    doc.setFont("helvetica", "bold"); doc.setFontSize(9); soft(); doc.text("BILL TO", M, y);
    doc.text("LOAD", W / 2, y); y += 14;
    doc.setFont("helvetica", "normal"); doc.setFontSize(11); ink();
    const billLines = [f.broker || "—", f.broker_mc && "MC " + f.broker_mc, f.broker_email].filter(Boolean);
    billLines.forEach((s, i) => doc.text(String(s), M, y + i * 14));
    const loadRows = [["Load #", f.load_no], ["BOL #", f.bol_no], ["PO #", f.po_no], ["Delivered", f.del_date]].filter((r) => r[1]);
    loadRows.forEach(([k, v], i) => { soft(); doc.text(k, W / 2, y + i * 14); ink(); doc.text(String(v), W / 2 + 70, y + i * 14); });
    y += Math.max(billLines.length, loadRows.length) * 14 + 16;

    const stop = (label, val) => {
      if (!val) return;
      doc.setFont("helvetica", "bold"); doc.setFontSize(9); soft(); doc.text(label, M, y); y += 13;
      doc.setFont("helvetica", "normal"); doc.setFontSize(11); ink();
      const wrapped = doc.splitTextToSize(String(val), W - 2 * M);
      doc.text(wrapped, M, y); y += wrapped.length * 14 + 8;
    };
    stop("PICKUP / SHIPPER", f.shipper);
    stop("DELIVERY / CONSIGNEE", f.consignee);

    y += 6; doc.setLineWidth(1.2); doc.line(M, y, W - M, y); y += 18;
    doc.setFont("helvetica", "bold"); doc.setFontSize(9); soft();
    doc.text("DESCRIPTION", M, y); doc.text("AMOUNT", W - M, y, { align: "right" }); y += 16;
    doc.setFont("helvetica", "normal"); doc.setFontSize(11); ink();
    const charges = [["Linehaul", f.rate], ["Detention", f.detention], ["Lumper (receipt attached)", f.lumper], ["Other", f.other]].filter((r) => num(r[1]));
    charges.forEach(([k, v]) => { doc.text(k, M, y); doc.text(usd(num(v)), W - M, y, { align: "right" }); y += 16; });
    if (f.notes) { soft(); const w = doc.splitTextToSize(f.notes, W - 2 * M - 120); doc.text(w, M, y); y += w.length * 13; ink(); }
    y += 4; doc.setLineWidth(2); doc.line(W / 2, y, W - M, y); y += 22;
    doc.setFont("helvetica", "bold"); doc.setFontSize(16);
    doc.text("TOTAL DUE", W / 2, y); doc.text(usd(totalOf(f)), W - M, y, { align: "right" }); y += 34;

    if (c.c_remit) {
      doc.setFillColor(243, 239, 230); const w = doc.splitTextToSize(c.c_remit, W - 2 * M - 24);
      const h = w.length * 14 + 30; doc.rect(M, y, W - 2 * M, h, "F");
      doc.setFontSize(9); soft(); doc.text("REMIT PAYMENT TO", M + 12, y + 16);
      doc.setFont("helvetica", "normal"); doc.setFontSize(11); ink(); doc.text(w, M + 12, y + 32); y += h + 16;
    }
    doc.setFontSize(9); soft();
    doc.text(`Attached: ${l.imgs.map((i) => i.kind).join(", ") || "no documents"}`, M, 760);
    doc.text("Built with PODsnap", W - M, 760, { align: "right" });

    for (const im of l.imgs) {
      const src = await imgGet(im.id); if (!src) continue;
      const img = await loadImg(src);
      doc.addPage();
      const bw = W - 2 * 24, bh = 792 - 2 * 24 - 16;
      const s = Math.min(bw / img.naturalWidth, bh / img.naturalHeight);
      const iw = img.naturalWidth * s, ih = img.naturalHeight * s;
      doc.addImage(src, "JPEG", (W - iw) / 2, 24 + 16, iw, ih);
      doc.setFontSize(9); soft(); doc.text(`${im.kind} · Invoice ${l.invNo} · Load ${f.load_no || "—"}`, 24, 24 + 8);
    }
    const name = `Invoice-${l.invNo}${f.load_no ? "-Load-" + f.load_no.replace(/[^\w\-]/g, "") : ""}.pdf`;
    return new File([doc.output("blob")], name, { type: "application/pdf" });
  }

  function emailParts() {
    const l = cur(), f = l.f;
    const to = f.broker_email || carrier.c_factor || "";
    const subject = `Invoice ${l.invNo} — Load ${f.load_no || ""} — ${carrier.c_name || ""}`.trim();
    const body = [
      "Hello,", "",
      `Attached is invoice ${l.invNo} with BOL/POD for load ${f.load_no || "(see attached)"}.`,
      `Amount due: ${usd(totalOf(f))}`, f.del_date ? `Delivered: ${f.del_date}` : "", "",
      "Thank you,", carrier.c_name || "", carrier.c_mc ? "MC/DOT " + carrier.c_mc : "", carrier.c_phone || ""
    ].filter((s, i, a) => s !== "" || a[i - 1] !== "").join("\n");
    return { to, subject, body };
  }

  $("#packetBtn").addEventListener("click", async () => {
    const st = $("#packetStatus"), l = cur();
    const missing = $$("[data-chk]").filter((c) => !c.checked).length;
    st.className = "status"; st.textContent = "Building PDF…";
    try {
      lastPacket = await buildPacket();
      const { subject, body } = emailParts();
      if (navigator.canShare && navigator.canShare({ files: [lastPacket] })) {
        try { await navigator.share({ files: [lastPacket], title: subject, text: body }); }
        catch (e) { if (e.name !== "AbortError") throw e; }
      } else {
        const a = document.createElement("a"); a.href = URL.createObjectURL(lastPacket); a.download = lastPacket.name;
        document.body.appendChild(a); a.click(); a.remove(); setTimeout(() => URL.revokeObjectURL(a.href), 5000);
      }
      st.className = "status ok";
      st.textContent = `${lastPacket.name} · ${l.imgs.length + 1} pages` + (missing ? ` · ${missing} check${missing > 1 ? "s" : ""} unticked` : "");
    } catch (e) {
      st.textContent = /offline|Failed/i.test(String(e)) ? "PDF tool needs a connection the first time." : "Couldn't build the PDF: " + e.message;
    }
  });

  $("#emailBtn").addEventListener("click", async () => {
    const { to, subject, body } = emailParts();
    if (lastPacket && navigator.canShare && navigator.canShare({ files: [lastPacket] })) {
      try { await navigator.share({ files: [lastPacket], title: subject, text: body }); return; } catch (e) { if (e.name === "AbortError") return; }
    }
    location.href = `mailto:${encodeURIComponent(to)}?subject=${encodeURIComponent(subject)}&body=${encodeURIComponent(body + "\n\n(Packet PDF attached)")}`;
  });

  // ---------- price text from config ----------
  $$("[data-price='monthly']").forEach((el) => (el.textContent = CFG.PRICE_MONTHLY || 14));

  // ---------- boot ----------
  window.PODsnap = { extract };
  if (!loads[currentId]) { const any = Object.keys(loads)[0]; currentId = any || null; }
  cur();
  paintForm();
  setPane(ls.get(K.pane, "docs"));
  if ("serviceWorker" in navigator && location.protocol === "https:") navigator.serviceWorker.register("sw.js").catch(() => {});
})();
