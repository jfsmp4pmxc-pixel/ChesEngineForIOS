// Runs Stockfish inside the app process and talks UCI to it through in-memory
// queues instead of stdin/stdout. Stockfish's own main() is renamed to
// stockfish_main at compile time (-Dmain=stockfish_main for main.cpp only).

#include "StockfishBridge.h"

#include <pthread.h>
#include <unistd.h>

#include <chrono>
#include <condition_variable>
#include <cstring>
#include <deque>
#include <iostream>
#include <mutex>
#include <streambuf>
#include <string>

extern int stockfish_main(int argc, char *argv[]);

namespace {

struct LineQueue {
    std::mutex m;
    std::condition_variable cv;
    std::deque<std::string> q;
    bool closed = false;

    void push(std::string s) {
        {
            std::lock_guard<std::mutex> l(m);
            q.push_back(std::move(s));
        }
        cv.notify_one();
    }

    void close() {
        {
            std::lock_guard<std::mutex> l(m);
            closed = true;
        }
        cv.notify_all();
    }

    // timeoutMs < 0 waits forever. Returns 1 got line, 0 timeout, -1 closed and empty.
    int pop(std::string &out, int timeoutMs) {
        std::unique_lock<std::mutex> l(m);
        auto ready = [&] { return !q.empty() || closed; };
        if (timeoutMs < 0) {
            cv.wait(l, ready);
        } else {
            cv.wait_for(l, std::chrono::milliseconds(timeoutMs), ready);
        }
        if (!q.empty()) {
            out = std::move(q.front());
            q.pop_front();
            return 1;
        }
        return closed ? -1 : 0;
    }
};

LineQueue toEngine;
LineQueue fromEngine;

// std::cin replacement: hands Stockfish one queued command line at a time.
class InBuf : public std::streambuf {
    std::string cur;

protected:
    int_type underflow() override {
        if (gptr() < egptr()) return traits_type::to_int_type(*gptr());
        std::string line;
        if (toEngine.pop(line, -1) != 1) return traits_type::eof();
        cur = line + "\n";
        setg(&cur[0], &cur[0], &cur[0] + cur.size());
        return traits_type::to_int_type(*gptr());
    }
};

// std::cout replacement: splits the output stream into lines.
class OutBuf : public std::streambuf {
    std::string buf;

protected:
    int_type overflow(int_type c) override {
        if (traits_type::eq_int_type(c, traits_type::eof())) return traits_type::not_eof(c);
        char ch = traits_type::to_char_type(c);
        if (ch == '\n') {
            fromEngine.push(buf);
            buf.clear();
        } else if (ch != '\r') {
            buf.push_back(ch);
        }
        return c;
    }

    std::streamsize xsputn(const char *s, std::streamsize n) override {
        for (std::streamsize i = 0; i < n; ++i) overflow(traits_type::to_int_type(s[i]));
        return n;
    }
};

InBuf inBuf;
OutBuf outBuf;
std::mutex startMutex;
bool started = false;
char *engineArgv[2] = {nullptr, nullptr};

void *engineThread(void *) {
    stockfish_main(1, engineArgv);
    fromEngine.close();
    return nullptr;
}

} // namespace

extern "C" {

int sf_start(const char *argv0) {
    std::lock_guard<std::mutex> l(startMutex);
    if (started) return 1;
    if (!argv0) return -1;

    engineArgv[0] = strdup(argv0);

    // Stockfish looks for the networks next to argv[0] and in the working
    // directory; make both point at the folder that holds them.
    std::string dir(argv0);
    size_t slash = dir.find_last_of('/');
    if (slash != std::string::npos && slash > 0) {
        dir.resize(slash);
        chdir(dir.c_str());
    }

    std::cin.rdbuf(&inBuf);
    std::cout.rdbuf(&outBuf);

    pthread_attr_t attr;
    pthread_attr_init(&attr);
    pthread_attr_setstacksize(&attr, 8 * 1024 * 1024);
    pthread_t tid;
    int rc = pthread_create(&tid, &attr, engineThread, nullptr);
    pthread_attr_destroy(&attr);
    if (rc != 0) return -2;
    pthread_detach(tid);

    started = true;
    return 0;
}

void sf_send(const char *command) {
    if (!command) return;
    toEngine.push(std::string(command));
}

int sf_read(char *buffer, int capacity, int timeout_ms) {
    if (!buffer || capacity <= 0) return -1;
    std::string line;
    int rc = fromEngine.pop(line, timeout_ms);
    if (rc == 0) return -2;
    if (rc < 0) return -1;
    size_t n = line.size();
    if (n > (size_t)capacity - 1) n = (size_t)capacity - 1;
    memcpy(buffer, line.data(), n);
    buffer[n] = '\0';
    return (int)n;
}

} // extern "C"
