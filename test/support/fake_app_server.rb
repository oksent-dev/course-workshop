require "json"
$stdout.sync = true
STDIN.each_line do |line|
  request = JSON.parse(line)
  next unless request["id"]
  response = case request["method"]
  when "initialize"
    { result: { userAgent: "fake-server" } }
  when "echo"
    { result: request["params"] }
  when "fail"
    { error: { code: -32600, message: "A runtime error" } }
  when "close"
    exit
  else
    { result: {} }
  end
  puts JSON.generate(response.merge(id: request["id"]))
end
