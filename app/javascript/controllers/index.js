import { application } from "./application.js";
import ConversationController from "./conversation_controller.js";
import LessonImageController from "./lesson_image_controller.js";
import LessonBlockController from "./lesson_block_controller.js";
import GenerationController from "./generation_controller.js";
import LessonChatController from "./lesson_chat_controller.js";
import LanguageMenuController from "./language_menu_controller.js";
import AiSettingsController from "./ai_settings_controller.js";

application.register("conversation", ConversationController);
application.register("lesson-image", LessonImageController);
application.register("course-cover", LessonImageController);
application.register("lesson-block", LessonBlockController);
application.register("generation", GenerationController);
application.register("lesson-chat", LessonChatController);
application.register("language-menu", LanguageMenuController);
application.register("ai-settings", AiSettingsController);
