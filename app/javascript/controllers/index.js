import { application } from "./application.js";
import ConversationController from "./conversation_controller.js";
import LessonImageController from "./lesson_image_controller.js";

application.register("conversation", ConversationController);
application.register("lesson-image", LessonImageController);
