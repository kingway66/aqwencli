### Bash 脚本 ，它接收两个参数：

#### APIKEY：要进行 Base64 编码的 API 密钥；
#### OUTPUTPATH：要写入apikey.json的文件路径(不包括文件名）。
#### 默认不会覆盖原有的apikey.json，如需要强制覆盖，可用--force作为第一个参数

example：
```
write_apikey.sh the_apikey /some/where/
write_apikey.sh the_apikey ../a_qwen_cli
write_apikey.sh --force the_apikey ../a_qwen_cli 
```
