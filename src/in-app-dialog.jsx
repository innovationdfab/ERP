import React, { useEffect, useRef, useState } from 'react';
import { createPortal } from 'react-dom';
import './in-app-dialog.css';

// A single sequential queue prevents overlapping confirmations and ensures each
// caller receives its own answer. No browser-native alert/confirm is used.
let nextId = 0;
const pending = [];
const listeners = new Set();
const notify = () => { for (const listener of listeners) listener(); };
function enqueue(message, type) {
  return new Promise(resolve => {
    pending.push({ id: ++nextId, message: String(message ?? ''), type, resolve });
    notify();
  });
}
export function showNotice(message) { return enqueue(message, 'notice'); }
export function askConfirmation(message) { return enqueue(message, 'confirm'); }
export function InAppDialogHost() {
  const [active, setActive] = useState(null);
  const buttonRef = useRef(null);
  useEffect(() => {
    const update = () => setActive(pending[0] || null);
    listeners.add(update);
    update();
    return () => listeners.delete(update);
  }, []);
  useEffect(() => { if (active) buttonRef.current?.focus(); }, [active]);
  const settle = answer => {
    if (!active) return;
    if (pending[0]?.id === active.id) pending.shift();
    active.resolve(answer);
    notify();
  };
  useEffect(() => {
    if (!active) return undefined;
    const keydown = e => {
      if (e.key === 'Escape') { e.preventDefault(); settle(false); }
      if (e.key === 'Tab') {
        const buttons = document.querySelectorAll('.erp-app-dialog button');
        if (!buttons.length) return;
        const first = buttons[0], last = buttons[buttons.length - 1];
        if (e.shiftKey && document.activeElement === first) { e.preventDefault(); last.focus(); }
        else if (!e.shiftKey && document.activeElement === last) { e.preventDefault(); first.focus(); }
      }
    };
    document.addEventListener('keydown', keydown);
    return () => document.removeEventListener('keydown', keydown);
  // settle uses only the currently displayed dialog.
  }, [active]);
  if (!active) return null;
  return createPortal(<div className="erp-dialog-scrim" role="presentation">
    <section className="erp-app-dialog" role="alertdialog" aria-modal="true" aria-labelledby="erp-dialog-title" aria-describedby="erp-dialog-content">
      <div className="erp-dialog-glyph" aria-hidden="true">{active.type === 'confirm' ? '?' : 'i'}</div>
      <h2 id="erp-dialog-title">{active.type === 'confirm' ? 'Please confirm' : 'ERP notification'}</h2>
      <p id="erp-dialog-content">{active.message}</p>
      <div className="erp-dialog-actions">
        {active.type === 'confirm' && <button ref={buttonRef} type="button" className="erp-dialog-cancel" onClick={() => settle(false)}>Cancel</button>}
        <button ref={active.type === 'notice' ? buttonRef : undefined} type="button" className="erp-dialog-accept" onClick={() => settle(true)}>{active.type === 'confirm' ? 'Confirm' : 'OK'}</button>
      </div>
    </section>
  </div>, document.body);
}
