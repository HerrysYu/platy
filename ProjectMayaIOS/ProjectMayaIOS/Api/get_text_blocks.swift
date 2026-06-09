//
//  get_text_blocks.swift
//  practice
//
//  Created by Herrys Yu on 5/21/25.
//
import Foundation
import UIKit
//===========================================================================================================================utlis
struct MenuBlocksResult:Codable {
    var text: String
    var angle: Double
    var box2D: [CGFloat]
    var translatedText: String?
}

struct MenuBlockResult:Codable{
    var blocks: [MenuBlocksResult]
}
func validateResult(result:MenuBlockResult) -> Bool {
    return true
}

func decodeResult(result: String) -> MenuBlockResult? {
    var decodedResult: MenuBlockResult!
    do{
        
        let decoded = try JSONDecoder().decode(MenuBlockResult.self, from: Data(result.utf8))
        guard validateResult(result:decoded) else {
            // throw exception
            return nil
        }
        decodedResult=decoded
        return decodedResult
    }catch {
        print("decoded error")
        return nil
    }
}

func getMenuBlock(result: String) -> MenuBlocks? {
    return getMenuBlocks(result:decodeResult(result:result)!) ?? nil
}

func getMenuBlocks(result:MenuBlockResult) -> MenuBlocks? {
    guard validateResult(result:result) else {
        // throw exception
        print("validate error")
        return nil
    }
    
    var textBlocks:[TextBlock] = []
    for blockResult in result.blocks {
        let menuBlocksResult:MenuBlocksResult=MenuBlocksResult(text: blockResult.text, angle: blockResult.angle, box2D: blockResult.box2D, translatedText: blockResult.translatedText)
        textBlocks.append(getTextBlock(result:menuBlocksResult))
    }
    return MenuBlocks(BlockList: BlockList(blocks: textBlocks))
}

func getTextBlock(result:MenuBlocksResult) -> TextBlock {
    return TextBlock(
        text: result.text,
        angle: result.angle,
        box2D: result.box2D,
        translatedText: result.translatedText
    )
}

//=========================================================================================================================== handle BlockList
func translationApi( imageList: [UIImage], completion: @escaping ([MenuImage]?,[MenuBlocks]?) -> Void) {
    var menuImageList: [MenuImage]=[]
    var menuBlockList: [MenuBlocks] = []
    let dispatchGroup = DispatchGroup()
    for image in imageList{
        let menuImage = MenuImage(
            image: image,
            height: Double(image.size.height),
            width: Double(image.size.width),
        )
        menuImageList.append(menuImage)
    }
    for image in imageList {
        dispatchGroup.enter()
        do {
            print("calling getTextBlocksList")
            // 调用你之前实现的上传/分析函数（返回 BlockList）
            getTextBlocksList(image: image) { result in
                if result == nil  {
                    print("menu handling error")
                } else {
                    //let menuBlock = MenuBlocks(BlockList: result!)
                    let menuBlock = getMenuBlock(result:result!)
                    menuBlockList.append(menuBlock!)
                }
                dispatchGroup.leave()
            }
        } catch {
            print("写入临时文件失败: \(error)")
            dispatchGroup.leave()
        }
    }

    dispatchGroup.notify(queue: .main) {
        completion(menuImageList.isEmpty ? nil : menuImageList,menuBlockList.isEmpty ? nil : menuBlockList)
    }
}

//=========================================================================================================================== getTextBlocks
func getTextBlocksList(image: UIImage, completion: @escaping (String?) -> Void) {
    onlyUploadFile(image: image, api: "ocr?source_lang=PleaseRecogizeTheLanguageAutomatically&target_lang=English") { result in
        print(result)
        guard let result = result else {
            print("Received blocks are null")
            completion(nil)
            return
        }

        do {
            let jsonData = Data(result.utf8)
            let decoded = try JSONDecoder().decode(BlockList.self, from: jsonData)
            completion(result)
        } catch {
            print("JSON Decode error: \(error)")
            completion(nil)
        }
    }
}
//============================================================================================================================ handle file uploading
func onlyUploadFile(image: UIImage, api: String, completion: @escaping (String?) -> Void) {
    guard let imageData = image.jpegData(compressionQuality: 1) else {
        print("UIImage: \(image)")
        print("无法获取 JPEG 数据")
        completion(nil)
        return
    }

    let boundary = UUID().uuidString
    let url = URL(string: baseurl+"/\(api)")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

    var body = Data()

    // 添加 file 字段（关键是名字要为 "file"）
    body.append("--\(boundary)\r\n".data(using: .utf8)!)
    body.append("Content-Disposition: form-data; name=\"file\"; filename=\"image.jpg\"\r\n".data(using: .utf8)!)
    body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
    body.append(imageData)
    body.append("\r\n".data(using: .utf8)!)
    body.append("--\(boundary)--\r\n".data(using: .utf8)!)

    request.httpBody = body

    let task = URLSession.shared.dataTask(with: request) { data, response, error in
        if let error = error {
            print("请求出错: \(error)")
            completion(nil)
            return
        }

        guard let httpResponse = response as? HTTPURLResponse,
              let responseData = data else {
            print("响应无效")
            completion(nil)
            return
        }

        if httpResponse.statusCode == 200 {
            let resultString = String(data: responseData, encoding: .utf8)
            completion(resultString)
        } else {
            print("上传失败: \(httpResponse.statusCode), body: \(String(data: responseData, encoding: .utf8) ?? "")")
            completion(nil)
        }
    }

    task.resume()
}
