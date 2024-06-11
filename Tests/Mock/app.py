import random
from flask import Flask, make_response, request, Response

app = Flask(__name__)


class PerformanceServerTiming:
    def __init__(self, name, description, duration):
        self.name = name
        self.description = description
        self.duration = duration


def _generate_performance_server_timing() -> PerformanceServerTiming:
    chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890_-"
    desc_len = random.randrange(0, 10)
    chars_len = len(chars)
    description = ""

    for i in range(desc_len):
        index = random.randrange(0, chars_len)
        description += chars[index]

    name_len = random.randrange(1, 10)
    name = ""
    for i in range(name_len):
        index = random.randrange(0, chars_len)
        name += chars[index]

    duration = random.uniform(0.1, 500.0)
    return PerformanceServerTiming(name, description, duration)


def _generate_response(desired_status_code) -> Response:
    try:
        desired_status_code = int(desired_status_code)
    except:
        return make_response("Invalid Status-Code in the HTTP Header", 404)
    response = make_response("Hello from lcl-ping mock server!\n")
    response.status_code = desired_status_code
    return response


@app.route("/", methods=['GET'])
def get():
    desired_status_code = request.headers.get("Status-Code", 200)
    return _generate_response(desired_status_code=desired_status_code)


@app.route("/server-timing", methods=['GET'])
def get_server_timing():
    use_empty_server_timing = request.headers.get("Use-Empty-Server-Timing", "False")
    use_empty_server_timing = use_empty_server_timing.lower() in ['true', 'yes']

    num_server_timing_metrics = request.headers.get("Number-Of-Metrics", 1)
    try:
        num_server_timing_metrics = int(num_server_timing_metrics)
    except:
        num_server_timing_metrics = 1
    desired_status_code = request.headers.get("Status-Code", 200)
    
    response = _generate_response(desired_status_code=desired_status_code)
    if not use_empty_server_timing:
        response.headers.set("Server-Timing", "")
    else:
        res = ""
        for i in range(num_server_timing_metrics):
            server_timing_metric = _generate_performance_server_timing()
            res += f"{server_timing_metric.name};"
            if server_timing_metric.description:
                res += f"desc=\"{server_timing_metric.description}\";"
            res += f"dur={server_timing_metric.duration}"
            if i != num_server_timing_metrics - 1:
                res += ", "
        response.headers.set("Server-Timing", res)
    print(f"response header is {response.headers}")
    return response
        
