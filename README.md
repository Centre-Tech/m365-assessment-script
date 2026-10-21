# m365-assessment-script

One-shot Microsoft 365 tenant assessment. Paste a single line into the
Microsoft 365 admin center **Cloud Shell (Bash)** and walk away with a
zip containing a full tenant inventory *and* a security review: Conditional
Access, admin roles, MFA registration, guest access, legacy auth, OAuth app
consent risk, Identity Protection risk signals, and Secure Score.

## Quick start (one line)

Open Cloud Shell in **Bash** mode (top-left "Switch to Bash" button if it's in
PowerShell), then paste:

```bash
curl -s https://raw.githubusercontent.com/arieldavenport/m365-assessment-script/main/m365-assessment.sh | bash
```

Cloud Shell pops the file-download dialog at the end with the zip
pre-selected. No second sign-in (reuses your existing Azure CLI session),
no module installs, no Conditional Access friction.

Need different options? Pass arguments through:

```bash
curl -s https://raw.githubusercontent.com/arieldavenport/m365-assessment-script/main/m365-assessment.sh | bash -s -- --stale-days 60
```

## What you get

| File in zip | What's in it |
| --- | --- |
| `M365_Users_<tenant>_<ts>.csv`        | Mirrors the admin center "Active users" export plus sign-in activity (last interactive / non-interactive / successful sign-in, days since last activity). |
| `M365_Products_<tenant>_<ts>.csv`     | One row per license subscription across all billing accounts (total / consumed / available licenses, service plans, renewal date, friendly product names), plus `BillingAccount`, `BillingAgreementType` (MCA / MOSA / EA / MPA), `BillingProfile`, `Reseller` and `AutoRenew` from the Azure Billing API. Subscriptions not found in any billing account the signed-in user can read (CSP partner or legacy MOSA) are labeled as such. |
| `M365_LicenseReconciliation_<tenant>_<ts>.csv` | One row per product: total licenses split into those on a readable billing account, those on subscriptions that couldn't be placed on one (CSP partner or legacy MOSA), and those with no subscription record at all. Any product not fully accounted for is flagged `CHECK`; free/self-service SKUs are labeled as such. |
| `M365_StaleUsers_<tenant>_<ts>.csv`   | Enabled, non-guest accounts whose most recent sign-in is older than `--stale-days` (default 90), or that have never signed in and were created longer ago than the threshold. |
| `M365_ConditionalAccessPolicies_<tenant>_<ts>.csv` | Every Conditional Access policy: state, scope (users/apps/client app types), grant/session controls. |
| `M365_AdminRoleAssignments_<tenant>_<ts>.csv` | Active Microsoft Entra directory role assignments, flagged by whether the role is high-privilege. |
| `M365_MFARegistration_<tenant>_<ts>.csv` | Per-user authentication method registration: MFA/SSPR/passwordless status, `IsAdmin`, methods registered. |
| `M365_GuestUsers_<tenant>_<ts>.csv`   | Guest (B2B) accounts, same columns as the Users CSV. |
| `M365_LegacyAuthSignIns_<tenant>_<ts>.csv` | Sign-ins using legacy/basic auth protocols (IMAP, POP, ActiveSync, etc.) in the lookback window, aggregated by user/app/client. |
| `M365_OAuthConsent_<tenant>_<ts>.csv` | Every delegated and application permission grant to an enterprise app, with high-risk permissions flagged. |
| `M365_RiskyUsers_<tenant>_<ts>.csv`   | Microsoft Entra ID Protection risky users (requires Entra ID P2). |
| `M365_SecureScore_<tenant>_<ts>.csv`  | Microsoft Secure Score, per control, worst-implemented first. |
| `M365_SecurityFindings_<tenant>_<ts>.csv` | Consolidated High/Medium/Low findings synthesized across all of the above, sorted by severity. App consent findings are one row per third-party app (listing its high-risk permissions, admin consent and user-consent count); service principals holding Global Administrator are flagged separately from the human Global Admin count. |
| `M365_E5ToBusinessPremium_<tenant>_<ts>.csv` | One row per Microsoft 365 E5 user with a `Recommendation`: **Keep E5** (mailbox over 50 GB, or custodian in an open eDiscovery case), **Review** (holds an admin role, mailbox 40–50 GB, or has a Windows Enterprise device), **Business Premium + add-ons** (Teams Phone Standard if they have a phone number or calling plan with Phone System only from E5; Power BI Pro if they used Power BI in the last 28 days; Entra ID P2 if PIM-eligible or covered by a risk-based Conditional Access policy), **Business Premium**, or **Remove license (inactive)**. If any check couldn't run, Business Premium recommendations get an **(unverified)** suffix. `Reasons` explains each call; `NotChecked` lists the data sources that couldn't be read. Run with `--extended` for full coverage. |

## Options

| Flag | Default | Notes |
| --- | --- | --- |
| `--tenant ID\|DOMAIN`    | current session | Target tenant for the Graph token. Use when assessing a customer tenant via a partner (GDAP) account; run `az login --tenant <ID> --allow-no-subscriptions --use-device-code` first. If a GUID is given, the script aborts if Graph reports a different tenant. |
| `--extended`             | off         | Adds a second device-code sign-in (Microsoft Graph Command Line Tools app) for data the Cloud Shell Azure CLI token can't access: Secure Score, risky users, and for the E5 fit check, mailbox sizes, Teams phone numbers, PIM eligibility, eDiscovery custodians and Intune devices. The code prompt appears right after `Connected to:`; sign in once and the rest of the run is unattended. First use in a tenant (and after new permissions are added) needs a Global Admin to consent for the organization. |
| `--stale-days N`         | `90`        | Inactivity threshold for the stale-users CSV. |
| `--output-dir PATH`      | `$HOME`     | Where the CSVs / zip are written. |
| `--skip-friendly-names`  | off         | Skip downloading Microsoft's SKU friendly-name map; CSV keeps raw `SkuPartNumber` values. |
| `--skip-security-review` | off         | Skip the security review entirely and only produce the original Users/Products/StaleUsers CSVs. |
| `--skip-e5-fit`          | off         | Skip the per-user Microsoft 365 E5 → Business Premium fit check. |
| `--legacy-auth-days N`   | `7`         | Sign-in log lookback window for the legacy-auth scan. |
| `--no-download`          | off         | Don't auto-trigger the Cloud Shell download dialog; just print the zip path. |

## Requirements

- Microsoft 365 admin center / Azure Cloud Shell **Bash** mode (already has `az`, `curl`, `jq`, `zip`, `python3`).
- An account with at least **Global Reader** on the tenant.
- The Azure CLI session in Cloud Shell already covers Graph delegated permissions via `Directory.AccessAsUser.All` — enough for users, products, and most of the security review (Conditional Access, admin roles, MFA registration, guests, legacy auth, OAuth consent).
- Secure Score and risky users need `SecurityEvents.Read.All` / `IdentityRiskyUser.Read.All`, which the Azure CLI token never carries. Use `--extended` to collect them; without it those CSVs are header-only.
- `signInActivity` on user rows, MFA registration details, and the legacy-auth scan require `AuditLog.Read.All` consent on the Azure CLI app. If it's not granted, those exports still produce successfully but the relevant columns/CSVs are blank, and the stale list falls back to a created-date heuristic.
- Risky users (`M365_RiskyUsers_*.csv`) require an **Entra ID P2** license — on P1/free tenants the CSV is written with headers only.
- Every security-review sub-check degrades gracefully: if the signed-in account lacks the Graph permission for it, the script prints a warning, writes a header-only CSV, and continues rather than aborting.
- Billing account mapping uses the Azure Billing API with the same Cloud Shell session. Global Administrator, Global Reader or a billing role is enough to list billing accounts; if they can't be read, the `BillingAccount` column says `Unknown`.
- Large tenants: Graph throttling (HTTP 429) and transient 5xx errors are retried automatically (honoring `Retry-After`), and the Graph token is refreshed before it expires, so long runs complete unattended.
- Always check the `Connected to:` line at the start of the run. If you're signed in with a partner account, Cloud Shell may be pointed at your home tenant rather than the customer's; use `--tenant`.

## Troubleshooting

If a CSV comes back empty, run the diagnostic. It prints the signed-in identity, token scopes, and the HTTP status for each Graph and Billing endpoint the assessment uses:

```bash
curl -s https://raw.githubusercontent.com/arieldavenport/m365-assessment-script/main/diagnose.sh | bash
```

## Running locally

If you'd rather not pipe from `curl`:

```bash
wget https://raw.githubusercontent.com/arieldavenport/m365-assessment-script/main/m365-assessment.sh
chmod +x m365-assessment.sh
./m365-assessment.sh --stale-days 90
```
