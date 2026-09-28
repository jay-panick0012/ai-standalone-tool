# Single-image build that runs identically on AWS (ECS Fargate / App Runner)
# and Azure (Container Apps / App Service for Containers). No cloud-specific
# code inside the image — only the deployment target differs.

FROM node:18-slim

WORKDIR /app

COPY package.json ./
RUN npm install --omit=dev

COPY server ./server
COPY public ./public

ENV PORT=8080
EXPOSE 8080

CMD ["node", "server/index.js"]
