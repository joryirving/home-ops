FROM node:24-alpine

WORKDIR /app

COPY package*.json ./

RUN npm install --production

COPY . .

EXPOSE 3000

USER node

CMD ["node", "server.js"]
