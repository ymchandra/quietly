import { Router, type IRouter } from "express";

const router: IRouter = Router();

const GUTENDEX = "https://gutendex.com/books/";
const ALLOWED_PARAMS = ["search", "topic", "languages", "sort", "page"] as const;

// Proxy GET /api/books → gutendex.com/books/
// Gutendex sends no Access-Control-Allow-Origin header so browser clients
// (web preview, PWA) cannot call it directly. All catalog requests go through
// this endpoint which inherits the app-level cors() middleware.
router.get("/books", async (req, res) => {
  try {
    const params = new URLSearchParams();
    for (const key of ALLOWED_PARAMS) {
      const val = req.query[key];
      if (typeof val === "string" && val.trim()) {
        params.append(key, val.trim());
      }
    }

    const url = params.toString()
      ? `${GUTENDEX}?${params.toString()}`
      : GUTENDEX;

    const upstream = await fetch(url, {
      headers: {
        Accept: "application/json",
        "User-Agent": "Quietly/1.0 (proxy)",
      },
    });

    if (!upstream.ok) {
      req.log.error(
        { status: upstream.status, url },
        "gutendex upstream error",
      );
      res.status(upstream.status).json({ error: "Upstream error from Gutendex" });
      return;
    }

    const data = await upstream.json();
    // Cache for 10 minutes — catalog data rarely changes within a session.
    res.set("Cache-Control", "public, max-age=600");
    res.json(data);
  } catch (err) {
    req.log.error({ err }, "gutendex proxy /books error");
    res.status(502).json({ error: "Could not reach Project Gutenberg catalog" });
  }
});

// Proxy GET /api/books/:id → gutendex.com/books/:id/
router.get("/books/:id", async (req, res) => {
  const id = Number(req.params.id);
  if (!Number.isInteger(id) || id <= 0) {
    res.status(400).json({ error: "Invalid book id" });
    return;
  }

  try {
    const url = `${GUTENDEX}${id}/`;
    const upstream = await fetch(url, {
      headers: {
        Accept: "application/json",
        "User-Agent": "Quietly/1.0 (proxy)",
      },
    });

    if (!upstream.ok) {
      req.log.error({ status: upstream.status, id }, "gutendex upstream error");
      res.status(upstream.status).json({ error: "Book not found or upstream error" });
      return;
    }

    const data = await upstream.json();
    res.set("Cache-Control", "public, max-age=3600"); // book metadata is stable
    res.json(data);
  } catch (err) {
    req.log.error({ err }, "gutendex proxy /books/:id error");
    res.status(502).json({ error: "Could not reach Project Gutenberg catalog" });
  }
});

export default router;
