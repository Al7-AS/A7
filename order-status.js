import { COURSES } from "../lib/courses.js";
import { sb } from "../lib/supabase.js";

const UUID_RE = /^[0-9a-f-]{36}$/i;

// Returns the order status. Lesson content is returned ONLY for a paid order.
export default async function handler(req, res) {
  if (req.method !== "GET") return res.status(405).end();
  const id = String(req.query?.id || "");
  if (!UUID_RE.test(id)) return res.status(400).json({ error: "invalid_id" });

  const [order] = await sb(`orders?id=eq.${id}&select=id,course_id,status,paid_at`);
  if (!order) return res.status(404).json({ error: "not_found" });

  const course = COURSES[order.course_id];
  const body = { status: order.status, courseTitle: course?.title };
  if (order.status === "paid" && course) body.lessons = course.lessons;
  return res.status(200).json(body);
}
