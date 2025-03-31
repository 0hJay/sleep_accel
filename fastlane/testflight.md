# TestFlight Deployment for SleepAccel

This project uses GitHub Actions and Fastlane to automate building and deploying to TestFlight. Follow these steps to set up and deploy.

## Step 1: Fork the Repository
- Fork `github.com/0hJay/sleep_accel` into your GitHub account.

## Step 2: Add GitHub Secrets
- Go to Settings -> Secrets and variables -> Actions.
- Add the following secrets:
  - `TEAMID`: Your Apple Developer Team ID (find at developer.apple.com).
  - `FASTLANE_ISSUER_ID`: Issuer ID from App Store Connect API key.
  - `FASTLANE_KEY_ID`: Key ID from App Store Connect API key.
  - `FASTLANE_KEY`: The API key content (including -----BEGIN PRIVATE KEY----- and -----END PRIVATE KEY-----).
  - `GH_PAT`: GitHub Personal Access Token with `repo` and `workflow` scopes.
  - `MATCH_PASSWORD`: A password for Match (same for all repositories).
  - `APPLE_ID`: Your Apple ID email for TestFlight.

## Step 3: Run GitHub Actions
- Go to the "Actions" tab.
- Run the workflows in order:
  1. Validate Secrets
  2. Add Identifiers
  3. Create Certificates
  4. Build SleepAccel

## Step 4: TestFlight
- Once the build completes, the app will appear in App Store Connect under TestFlight.
- Add testers and start testing.
