//
//  RPServiceClient.swift
//
// Copyright (c) 2017 Florian PETIT <florianp37@me.com>
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
//

import Foundation
import Moya
import ObjectMapper

/**
 You should subclass or extend this class in order to make your API calls backed with Moya/Alamofire and returning ObjectMapper models
 */
open class RPServiceClient<Target> where Target : TargetType {
    /// A MoyaProvider initialized with a given Target implementing TargetType for your API
    var provider: MoyaProvider<Target>

    /**
     NetworkClient initializer.
     - parameter provider: your API's MoyaProvider
     */
    public init(provider: MoyaProvider<Target>) {
        self.provider = provider
    }

    /**
     An Array Request.
     - parameter target: your API Target
     - parameter success: a success closure to be executed when the request is successfull and that will initialize a result array of Mappable objects of the given type
     - parameter failure: a closure to be executed on failure and that will give the error that caused the failure
     - returns a Cancellable instance so the pending request can be cancelled during execution
     */
   open func requestArray<T: Mappable>(target: Target, success: @escaping (_ result: [T]) -> Void, failure: @escaping (_ error: RPServiceClientError) -> Void) -> Cancellable {
        let cancellable = self.requestJSON(target: target, success: { (json) -> Void in
            if let error = self.jsonResponseAsError(json: json) {
                failure(error)
                return
            }

            if let result:[T] = Mapper<T>().mapArray(JSONObject: json) {
                success(result)
            } else {
                failure(RPServiceClientError.InvalidMapping(json: json))
            }
        }, failure: { (error) -> Void in
            failure(error)
        })

        return cancellable
    }

    /**
     An Object Request.
     - parameter target: your API Target
     - parameter success: a success closure to be executed when the request is successfull and that will initialize a single Mappable object of the given type
     - parameter failure: a closure to be executed on failure and that will give the error that caused the failure
     - returns a Cancellable instance so the pending request can be cancelled during execution
     */
   open func requestObject<T: Mappable>(target: Target, success: @escaping (_ result: T) -> Void, failure: @escaping (_ error: RPServiceClientError) -> Void) -> Cancellable {
        let cancellable = self.requestJSON(target: target, success: { (json) -> Void in
            if let error = self.jsonResponseAsError(json: json) {
                failure(error)
                return
            }

            if let result = Mapper<T>().map(JSONObject: json) {
                success(result)
            } else {
                failure(RPServiceClientError.InvalidMapping(json: json))
            }
        }, failure: { (error) -> Void in
            failure(error)
        })

        return cancellable
    }

    /**
     A JSON Request.
     - parameter target: your API Target
     - parameter success: a success closure to be executed when the request is successfull and that will return Any json result
     - parameter failure: a closure to be executed on failure and that will give the error that caused the failure
     - returns a Cancellable instance so the pending request can be cancelled during execution
     */
    func requestJSON(target: Target, success: @escaping (_ json: Any) -> Void, failure: @escaping (_ error: RPServiceClientError) -> Void) -> Cancellable {
        let cancellable = self.provider.request(target, completion: { result in
            switch result {
            case let .success(response) where 200..<400 ~= response.statusCode:
                do {
                    let json = try response.mapJSON()
                    success(json)
                } catch (let error) {
                    failure(RPServiceClientError.JSONParsing(cause: error))
                }
            case let .success(response): // Success with status >= 400
                do {
                    let json = try response.mapJSON()
                    failure(RPServiceClientError.RequestError(json: json))
                } catch (let error) {
                    failure(RPServiceClientError.JSONParsing(cause: error))
                }
            case let .failure(error):
                failure(RPServiceClientError.RequestFailure(cause: error))
            }
        })
        return cancellable
    }

    /**
     Transforms json containing an error message into an Error.
     - parameter json: the json containing the error
     - returns the appropriate RPServiceClientError
     */
    func jsonResponseAsError(json: Any) -> RPServiceClientError? {
        if let result: ErrorResult = Mapper<ErrorResult>().map(JSONObject: json) {
            if result.isValidError() {
                return self.buildNetworkError(with: result)
            }
        }
        return nil
    }

    /**
     Builds the appropriate Error from an ErrorResult.
     - parameter errorResult: the ErrorResult Mapped object
     - returns a RPServiceClientError
     */
    func buildNetworkError(with errorResult: ErrorResult) -> RPServiceClientError {
        let errorMsg = errorResult.description
        let userInfo = [
            NSLocalizedDescriptionKey: errorMsg
        ]
        let error = NSError(domain: "RPServiceClientErrorDomain", code: 1001, userInfo: userInfo)
        let bufferError = RPServiceClientError.RequestFailure(cause: error)
        return bufferError
    }
}