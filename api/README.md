# 3105 license administration API

This Vercel Function is the only component allowed to use the Keygen administrator token.

Configure these Vercel environment variables:

- `KEYGEN_ACCOUNT_ID`: the Keygen account ID.
- `KEYGEN_SERVER_TOKEN`: a scoped Keygen environment or product token kept only on Vercel. Do not put it in the iOS project.
- `APP_ADMIN_TOKEN`: a separate long random secret used by the personal app to authenticate to this proxy. This is the code entered in the app; it is not a Keygen token.

Deploy the repository as a Vercel project, set the variables for Production, and redeploy. The app should call `/api/licenses` with `Authorization: Bearer <APP_ADMIN_TOKEN>`.

## Deployment

1. Import the GitHub repository into Vercel and keep the repository root as the project root.
2. Add the three variables under **Settings → Environment Variables** for **Production**.
3. Deploy or redeploy the project.
4. Copy the deployed URL and replace `AdminLicenseClient.apiURL` in `ThreeOneOSFive/helpers/AdminLicenseService.swift` with `https://YOUR-DOMAIN/api/licenses`.
5. Build the personal IPA after that change.

Generate `APP_ADMIN_TOKEN` as a separate long random value. Do not reuse the Keygen token. If either value is exposed, rotate it immediately in Vercel or Keygen.

The function supports listing, creating, suspending, reinstating, and revoking licenses. It applies a small in-memory per-IP request limit; keep the endpoint private and rotate `APP_ADMIN_TOKEN` if the app or token is shared.
