# Om Verma — Portfolio

## Open the website

**[Click here to open Om's portfolio](https://thevermaom.github.io/om-verma-portfolio/)**

No downloads or setup are needed. The first time it is published, GitHub may take a few minutes to make the page available.

## Open it on your computer

1. Download this project from GitHub using the green **Code** button and **Download ZIP**.
2. Extract the ZIP file.
3. Open the extracted `Resume` folder and double-click `index.html`.

## Run locally with Python (optional)

If Python is installed, open a terminal in this folder and run:

```sh
python -m http.server 8080
```

Then open [http://localhost:8080](http://localhost:8080) in your browser. Stop the server by pressing `Ctrl+C` in the terminal.

## Run with Docker (optional)

From this directory, build the image and start the site:

```sh
docker build -t om-verma-portfolio .
docker run --rm -p 8080:80 om-verma-portfolio
```

Open [http://localhost:8080](http://localhost:8080).

This is a static, responsive portfolio built with plain HTML, CSS, and JavaScript. It does not need a database, backend, build step, or JavaScript packages.
