**1. Install ngrok (Windows):**
```powershell
choco install ngrok
```
Or download from https://ngrok.com/download

**2. Configure ngrok:**
- Sign up at https://dashboard.ngrok.com/signup
- Get your authtoken and run:
```powershell
ngrok config add-authtoken YOUR_TOKEN
```

**3. Start ngrok tunnel:**
```powershell
ngrok http 8080
```

Copy the `https://` URL you see (e.g., `https://abc123.ngrok-free.app`)

**4. Add GitHub Webhook:**
- Go to your repo → Settings → Webhooks → Add webhook
- Payload URL: `https://YOUR_NGROK_URL/github-webhook/`
- Content type: `application/json`
- Events: "Just the push event"

**5. Ensure your Jenkins job has GitHub hook trigger enabled**

Now when you push code, Jenkins will automatically build! 

⚠️ **Note**: Free ngrok URLs change each restart, so you'll need to update the GitHub webhook URL each time you restart ngrok.

Made changes.