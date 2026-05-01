import { Router, type IRouter } from "express";
import healthRouter from "./health";
import gutendexRouter from "./gutendex";

const router: IRouter = Router();

router.use(healthRouter);
router.use(gutendexRouter);

export default router;
