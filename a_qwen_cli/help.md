## aqwencli主要是用于qwenlong，以下是其说明。

## 注意事项：
1. 本程序主要解决qwen-long和vl的原文件和原图片对话功能。
2. 单纯聊天或简单文件对话也能用，但其他客户端或网页可能更好用。
3. qwen-long-2025-01-25有免费额度，其余qwen-long没有。
4. 不支持多轮对话，实质是拼接，不如好好一次把提示词工程搞到位。
5. config.json中可以override温度等设置，请自行研究。
6. qwen-vl现在不支持目录上传。
7. qwen-long也可以识别图片，而且文字理解能力似乎比vl系列要强。

## 使用方法Useage:

假设你有下列目录结构（任意位置）if you have the dir structure:

```
-qwencli.sh
-1.txt
-2.txt
-1.png
-2.png
-docdir1
    -doc1.doc
    -doc2.pdf
-docdir2
    -foodresearch.xls
-picdir1
    -pic1.jpg
```


### chat with files(and dirs):

./qwencli.sh -m qwen-long-latest 1.txt 这个文件说了什么
./qwencli.sh -m qwen-long-latest 1.txt 2.txt 这两个文件有什么不一样
./qwencli.sh -m qwen-long-latest docdir2 这些文件关于食品研究的数据进行总结
./qwencli.sh -m qwen-long-latest 1.txt 2.txt docdir1 每个文件用200字总结
cat prompo.txt | ./qwencli.sh -m qwen-long-latest -i 1.png 2.png

### chat with imgs:

./qwencli.sh -m qwen-vl-latest 1.png 2.png 这些图片有什么关联
./qwencli.sh -m qwen-vl-latest 1.png picdir1 这些图片说了什么
cat prompt.txt | ./qwencli.sh -m qwen-vl-latest -i 1.png 2.png

### chat with texts:

./qwencli.sh -m qwen-turbo 讲个100字的笑话


### multiline texts(-dq decode question，换行转换成base64)

./qwencli.sh -m qwen-turbo -dq '讲个笑话 
                               英国的'

### save md to somewhere(maybe obisidian md path)

./qwencli.sh -m qwen-turbo -md ~/obisidian/llm_ref 讲个笑话

### cleanup(delete the files on the server you dont need):

USE THIS ONLY YOU SURE KNOW WHAT YOU ARE DOING
./qwencli.sh -m qwen-long-latest 1.txt 2.txt docdir1 --cleanup

### play with batch

make batch file
./qwencli.sh -m qwen-long-latest --batch batch1.json 1.txt docdir1 用300字对这些文件进行总结
create batch job
./qwencli.sh -m qwen-long-latest --runbatch batch1.json
get batch output（may use as cron）
./qwencli.sh -m qwen-long-latest --outbatch batch1.json

