---
title: Invoicing
group: Invoicing
order: 30
summary: Profiles, templates, regions, previewing, and exporting a PDF.
---

# Invoicing

An invoice is assembled from a project's time entries over a date range you choose, and can be viewed as an on-screen preview or exported as a PDF — both come from the same underlying document, so what you preview is what you get.

## Profiles and templates

Set these up once in Settings:

- **Profile:** your billing identity: business name, logo, contact details, bank/payment details, and which region and template it uses. This owns everything that appears on the invoice.
- **Template:** the visual look of the invoice (font and similar styling), chosen by a profile.

## Regions

A profile's **region** is your billing jurisdiction, and it drives several invoice details automatically:

- the tax label (e.g. GST for Australia, VAT for the UK and EU)
- the buyer's tax-ID label on the recipient block (e.g. ABN, VAT NO., TAX NO.)
- the default currency
- which bank/payment fields are shown (BSB and PayID for Australia, sort code and IBAN for the UK, routing number for the US, and so on)
- the page size the invoice prints at

> **Note:** Page size follows the region, not a manual setting — Australia, the UK, the EU, and Canada print on A4; the United States prints on Letter.

Australia is also the only region where a taxed invoice is titled "Tax Invoice" rather than plainly "Invoice".

## Previewing and exporting

Open a project's **Invoice** view, pick a date range, and the preview updates to show the itemised time entries for that period. When you're happy with it, export it as a PDF.

> **Tip:** Editing your profile — name, contact, rate, address, tax number, and so on — live-refreshes the open preview, so you can adjust details and see the result immediately.

Exporting behaves differently depending on platform:

- On desktop, exporting opens a native save dialog so you choose where the PDF file is written.
- On mobile, exporting hands the PDF to the platform's share sheet instead of writing a file directly.
