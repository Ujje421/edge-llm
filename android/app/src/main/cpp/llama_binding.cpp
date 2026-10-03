#include <jni.h>
#include <string>
#include <vector>
#include <android/log.h>
#include "llama.h"

#define TAG "LlamaBinding"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, TAG, __VA_ARGS__)

// Global pointers for the model and context
static llama_model* g_model = nullptr;
static llama_context* g_ctx = nullptr;

extern "C" JNIEXPORT jboolean JNICALL
Java_com_example_edgellm_MainActivity_loadModel(
        JNIEnv* env,
        jobject /* this */,
        jstring model_path,
        jint threads) {
    
    if (g_model != nullptr) {
        LOGI("Model is already loaded.");
        return JNI_TRUE;
    }

    const char *path = env->GetStringUTFChars(model_path, nullptr);
    LOGI("Loading model from path: %s with %d threads", path, threads);

    llama_backend_init();

    llama_model_params model_params = llama_model_default_params();
    g_model = llama_model_load_from_file(path, model_params);

    env->ReleaseStringUTFChars(model_path, path);

    if (g_model == nullptr) {
        LOGE("Failed to load model!");
        return JNI_FALSE;
    }

    llama_context_params ctx_params = llama_context_default_params();
    ctx_params.n_ctx = 1024; // Small context for expense extraction
    ctx_params.n_threads = threads;
    ctx_params.n_threads_batch = threads;
    
    g_ctx = llama_init_from_model(g_model, ctx_params);
    if (g_ctx == nullptr) {
        LOGE("Failed to create context!");
        llama_model_free(g_model);
        g_model = nullptr;
        return JNI_FALSE;
    }

    LOGI("Model loaded successfully!");
    return JNI_TRUE;
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_example_edgellm_MainActivity_promptModel(
        JNIEnv* env,
        jobject /* this */,
        jstring j_prompt) {

    if (g_model == nullptr || g_ctx == nullptr) {
        return env->NewStringUTF("Error: Model not loaded.");
    }

    const char *prompt_chars = env->GetStringUTFChars(j_prompt, nullptr);
    std::string prompt = prompt_chars;
    env->ReleaseStringUTFChars(j_prompt, prompt_chars);

    const struct llama_vocab * vocab = llama_model_get_vocab(g_model);

    // Tokenize
    std::vector<llama_token> tokens_list(prompt.length() + 8);
    int n_tokens = llama_tokenize(vocab, prompt.c_str(), prompt.length(), tokens_list.data(), tokens_list.size(), true, true);
    if (n_tokens < 0) {
        tokens_list.resize(-n_tokens);
        n_tokens = llama_tokenize(vocab, prompt.c_str(), prompt.length(), tokens_list.data(), tokens_list.size(), true, true);
    }

    // Prepare batch
    llama_batch batch = llama_batch_init(1024, 0, 1);
    
    // add tokens to batch
    for (int i = 0; i < n_tokens; i++) {
        batch.token[batch.n_tokens] = tokens_list[i];
        batch.pos[batch.n_tokens] = i;
        batch.n_seq_id[batch.n_tokens] = 1;
        batch.seq_id[batch.n_tokens][0] = 0;
        batch.logits[batch.n_tokens] = false;
        batch.n_tokens++;
    }
    // We only care about the logits for the last token of the prompt
    batch.logits[batch.n_tokens - 1] = true;

    if (llama_decode(g_ctx, batch) != 0) {
        llama_batch_free(batch);
        return env->NewStringUTF("Error: Failed to decode prompt.");
    }

    std::string result = "";
    int n_cur = batch.n_tokens;
    int n_predict = 100; // max length

    while (n_cur <= n_predict + n_tokens) {
        float * logits = llama_get_logits_ith(g_ctx, batch.n_tokens - 1);
        int n_vocab = llama_vocab_n_tokens(vocab);

        // Greedy sample (argmax)
        llama_token new_token_id = 0;
        float max_logit = -1e9;
        for (int i = 0; i < n_vocab; i++) {
            if (logits[i] > max_logit) {
                max_logit = logits[i];
                new_token_id = i;
            }
        }

        if (new_token_id == llama_vocab_eos(vocab)) {
            break;
        }

        char buf[128];
        int n = llama_token_to_piece(vocab, new_token_id, buf, sizeof(buf), 0, true);
        if (n >= 0) {
            result += std::string(buf, n);
        }

        // prepare next batch
        batch.n_tokens = 0; // equivalent to clear
        batch.token[batch.n_tokens] = new_token_id;
        batch.pos[batch.n_tokens] = n_cur;
        batch.n_seq_id[batch.n_tokens] = 1;
        batch.seq_id[batch.n_tokens][0] = 0;
        batch.logits[batch.n_tokens] = true;
        batch.n_tokens++;
        
        n_cur += 1;

        if (llama_decode(g_ctx, batch)) {
            break;
        }
    }

    llama_batch_free(batch);

    return env->NewStringUTF(result.c_str());
}
