import { application } from "./application.js";
import ConversationController from "./conversation_controller.js";
import LessonImageController from "./lesson_image_controller.js";
import LessonBlockController from "./lesson_block_controller.js";
import GenerationController from "./generation_controller.js";

application.register("conversation", ConversationController);
application.register("lesson-image", LessonImageController);
application.register("lesson-block", LessonBlockController);
application.register("generation", GenerationController);
