# Jenkins + Node.js build optimization

---

## 🚀 Optimizing `npm install` in Jenkins CI for Node.js Projects

This guide shows how I improved build speed for a **Node.js frontend application** running inside a **Jenkins CI/CD pipeline** by applying caching, smart installs, and best practices.

---

## ✅ Key Optimizations

- Replaced `npm install` with `npm ci`  
- Cached dependencies using `.npm` cache  
- Added `.npmrc` for smarter network behavior  
- Skipped reinstalling when dependencies haven't changed  
- Used Dockerfile layer caching for image builds

---

## 📁 Project Structure

```
project-root/
├── frontend/
│   ├── package.json
│   ├── package-lock.json
│   └── .npmrc
├── Jenkinsfile
└── docker-compose.yml
```

---

## ⚙️ Jenkinsfile Snippet

```groovy
stage('Install Dependencies') {
    when {
        changeset 'frontend/package*.json'
    }
    steps {
        dir('frontend') {
            sh 'npm ci --cache ~/.npm --prefer-offline'
        }
    }
}
```

---

## ⚙️ Docker Compose Volume (Optional)

To persist NPM cache across builds, mount the cache directory in your Jenkins agent container:

```yaml
volumes:
  - ~/.npm:/home/jenkins/.npm
```

---

## 📦 Sample `.npmrc`

```ini
progress=false
prefer-offline=true
fetch-retries=3
fetch-retry-mintimeout=10000
fetch-retry-maxtimeout=60000
```

---

## 🐳 Dockerfile Layer Caching

```dockerfile
FROM node:21-alpine
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
CMD ["npm", "start"]
```

---

## 🧪 References

- [Faster NPM Installs During CI — Tiernok](http://www.tiernok.com/posts/2019/faster-npm-installs-during-ci)
- [NPM Caching — Rubén Alapont](https://medium.com/@ruben.alapont/npm-caching-speeding-up-your-development-process-340dcdc554b3)

---

## ⏱️ Results

| Step           | Before | After  |
|----------------|--------|--------|
| `npm install`  | 3–5 min| < 1 min|
| Total pipeline | ~7 min | ~2.5 min|

---

## 🙌 Contributing

Feel free to fork or submit a PR with improvements or your own Jenkins caching tricks!

---

## 📬 Questions?

Open an issue or connect with me on [LinkedIn](https://www.linkedin.com/notharshhaa).
