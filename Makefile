SERVER_PORT=8080

.PHONY: debug_build
debug_build:
	swift build
	
.PHONY: test
test:
	make setup_server
	swift test --parallel -Xswiftc -DINTEGRATION_TEST
	make teardown_server


.PHONY: debug_unit_test
debug_unit_test:
	swift test --skip IntegrationTests
	
.PHONY: server_environment
server_environment:
	python3 -m pip install -r Mock/requirements.txt

.PHONY: setup_server
setup_server: server_environment
	flask --app Mock/app.py run --port $(SERVER_PORT)
	
	
.PHONY: teardown_server
teardown_server:
	kill -9 $(ps -ef | grep "flask --app Mock/app.py run" | grep -v "grep" | awk '{print $2}')
	rm -rf venv
	

.PHONY: debug_integration_test
debug_integration_test:
	make setup_server
	swift test -Xswiftc -DINTEGRATION_TEST --filter IntegrationTests
	make teardown_server


.PHONY: release
release: test
	swift build --release
	

.PHONY: clean
clean:
	rm -rf .build .swiftpm Package.resolved || true
